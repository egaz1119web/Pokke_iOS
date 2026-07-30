import Combine
import FirebaseFirestore
import Foundation

/// StashRepository の状態を Firestore の users/{uid} ドキュメント1件へ同期する。
///
/// Android版と同じドキュメント・同じJSONスキーマを使うので、同じGoogleアカウントで
/// ログインすればAndroid端末とiPhoneの間でそのまま同期される。
///
/// 素朴に「変更のたびに丸ごと上書き」すると2つの事故が起きるので、それぞれ対策している。
///  - 新しい端末でサインインした瞬間、空のローカル状態がクラウドを消してしまう
///    → サーバー確認済みのスナップショットを受け取るまで送信を止める（pushEnabled）
///  - 2台で編集すると後勝ちで片方の変更が消える
///    → 受信はレコード単位のマージ（StashMerge）にして、消さずに合流させる
@MainActor
final class FirestoreSync: ObservableObject {

    static let shared = FirestoreSync()

    private static let fieldState = "state"
    private static let fieldUpdatedAt = "updatedAt"

    /// 連続した編集で毎回書き込まないための待ち時間
    private static let pushDebounce: TimeInterval = 1.2

    /// 書き込み完了を待つ上限。オフライン中のFirestoreの書き込みは失敗せず保留され続けるため、
    /// ここで打ち切って「保留中」と表示する（書き込み自体はローカルキューに残り、復帰時に送られる）。
    private static let pushTimeoutSeconds: TimeInterval = 15

    /// Firestoreの1ドキュメント上限は1MiB。近づいたら送信を止めて理由を出す
    private static let maxDocumentBytes = 900 * 1024

    enum Status: Equatable {
        /// 未サインイン。同期していない
        case off
        /// サーバーの内容を確認中。まだ送信はしない
        case connecting
        /// 送信中
        case syncing
        /// オフラインで送信待ち。接続が戻れば自動的に送られる
        case pending
        case synced(at: EpochMillis)
        /// 表示文言はUI層で解決する。detail は %1$@ に差し込む補足（原因の生メッセージなど）
        case failure(messageKey: String, detail: String?)
    }

    @Published private(set) var status: Status = .off

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var pushCancellable: AnyCancellable?
    private var pushTask: Task<Void, Never>?
    private var currentUid: String?

    /// サーバー確認が取れるまでは送信しない。空の状態でクラウドを消さないための門番
    private var pushEnabled = false

    /// 確実にサーバー上にあると分かっている内容。これと同じなら送信しない
    private var knownRemoteJson: String?

    /// 直近でマージ済みのリモート内容。同じスナップショットを何度も解析しないための目印
    private var lastMergedJson: String?

    private init() {}

    /// サインインしたuidの同期を開始する
    func start(uid: String) {
        if currentUid == uid, listener != nil { return }
        teardown()
        currentUid = uid
        status = .connecting

        let docRef = userDoc(uid)

        // メタデータ変更も受け取る。isFromCache=false になった時点が「サーバー確認済み」
        listener = docRef.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.status = self.describe(error)
                    return
                }
                guard let snapshot else { return }
                self.onSnapshot(
                    json: snapshot.get(Self.fieldState) as? String,
                    fromCache: snapshot.metadata.isFromCache,
                    hasPendingWrites: snapshot.metadata.hasPendingWrites
                )
            }
        }

        pushCancellable = StashRepository.shared.$state
            .dropFirst()
            .debounce(for: .seconds(Self.pushDebounce), scheduler: DispatchQueue.main)
            .sink { [weak self] state in
                self?.schedulePush(state)
            }
    }

    /// サインアウト時に同期を止める
    func stop() {
        teardown()
        status = .off
    }

    /// クラウドに置いた内容（users/{uid} ドキュメント）を消す。アカウント削除の一部。
    ///
    /// 呼ぶ前に [stop] してリスナーと送信を止めておくこと。止めずに消すと、
    /// 手元の状態がそのまま書き戻されて消したはずの内容が復活する。
    /// 認証が生きているうちに消す必要もある（Firestoreルールが本人のドキュメントしか許さない）。
    func deleteRemoteData(uid: String) async throws {
        let docRef = userDoc(uid)
        // Firestoreはオフラインだと失敗を返さず保留し続けるので、push と同じく自前で打ち切る。
        // ここで諦めずにアカウントを消すと、誰も消せないドキュメントが残ってしまう
        let failure: Error? = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var finished = false
            func finish(_ error: Error?) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: error)
            }
            docRef.delete { error in finish(error) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pushTimeoutSeconds) {
                finish(DeleteError.timedOut)
            }
        }
        if let failure { throw failure }
    }

    enum DeleteError: LocalizedError {
        case timedOut

        var errorDescription: String? { L.s("sync_error_unavailable") }
    }

    /// 設定画面の「今すぐ同期」用。リスナーを張り直してサーバーの内容を取り直す
    func syncNow() {
        guard let uid = currentUid else { return }
        teardown()
        start(uid: uid)
    }

    private func userDoc(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func teardown() {
        listener?.remove()
        listener = nil
        pushCancellable?.cancel()
        pushCancellable = nil
        pushTask?.cancel()
        pushTask = nil
        currentUid = nil
        pushEnabled = false
        knownRemoteJson = nil
        lastMergedJson = nil
    }

    /// スナップショット1件の取り込み。
    /// ローカル書き込み直後にも（サーバー確認前に）呼ばれるので、
    /// 「サーバーにある」と断定できるのは キャッシュ由来でなく保留書き込みも無い時だけ。
    private func onSnapshot(json: String?, fromCache: Bool, hasPendingWrites: Bool) {
        let serverConfirmed = !fromCache && !hasPendingWrites

        if let json, json != lastMergedJson {
            lastMergedJson = json
            if let remote = StashJson.fromJson(json) {
                // マージ結果がリモートと違えば、この後のpushで差分が送り返される
                StashRepository.shared.mergeRemote(remote)
            }
        }

        if serverConfirmed {
            if let json { knownRemoteJson = json }
            // 保留していた書き込みがサーバーに届いた場合もここで完了になる
            if status == .syncing || status == .pending {
                status = .synced(at: nowMillis())
            }
        }

        // サーバーからの応答（ドキュメント未作成も含む）を確認できたら送信を解禁する
        if !fromCache { enablePush() }
    }

    /// サーバー確認が取れた。保留していたローカルの変更をここで初めて送る
    private func enablePush() {
        guard !pushEnabled else { return }
        pushEnabled = true
        schedulePush(StashRepository.shared.state)
    }

    private func schedulePush(_ state: StashState) {
        guard pushEnabled, let uid = currentUid else { return }
        let docRef = userDoc(uid)
        // 送信中に次の変更が来たら、前の送信は捨てて最新だけ送る（collectLatest相当）
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            await self?.push(docRef: docRef, state: state)
        }
    }

    private enum PushOutcome {
        case done
        case timedOut
        case failed(Error)
    }

    private func push(docRef: DocumentReference, state: StashState) async {
        guard pushEnabled else { return }
        let json = StashJson.toJson(state)
        if json == knownRemoteJson {
            // 既にサーバーと同じ内容。未同期の表示が残らないよう完了扱いにする
            if case .synced = status {} else { status = .synced(at: nowMillis()) }
            return
        }
        if json.utf8.count > Self.maxDocumentBytes {
            status = .failure(messageKey: "sync_error_too_large", detail: nil)
            return
        }

        status = .syncing
        let payload: [String: Any] = [
            Self.fieldState: json,
            Self.fieldUpdatedAt: nowMillis(),
        ]

        // Firestore はオフラインでも失敗を返さず保留し続ける（キャンセルにも応じない）ので、
        // 先に来た方を採用する形で自前に打ち切る
        let outcome: PushOutcome = await withCheckedContinuation { continuation in
            let lock = NSLock()
            var finished = false
            func finish(_ outcome: PushOutcome) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: outcome)
            }
            docRef.setData(payload, merge: true) { error in
                finish(error.map { PushOutcome.failed($0) } ?? .done)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pushTimeoutSeconds) {
                finish(.timedOut)
            }
        }

        guard !Task.isCancelled else { return }
        switch outcome {
        case .done:
            knownRemoteJson = json
            status = .synced(at: nowMillis())
        case .timedOut:
            // 書き込みはFirestoreのローカルキューに残っており、接続復帰時に自動送信される
            status = .pending
        case let .failed(error):
            status = describe(error)
        }
    }

    /// 原因が分かる文言に対応付ける。特にルール未設定は自力で気づけないので専用の案内を出す
    private func describe(_ error: Error) -> Status {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain,
              let code = FirestoreErrorCode.Code(rawValue: nsError.code)
        else {
            return .failure(messageKey: "sync_error_generic", detail: nsError.localizedDescription)
        }
        switch code {
        case .permissionDenied:
            return .failure(messageKey: "sync_error_permission_denied", detail: nil)
        case .unavailable:
            return .failure(messageKey: "sync_error_unavailable", detail: nil)
        case .unauthenticated:
            return .failure(messageKey: "sync_error_unauthenticated", detail: nil)
        default:
            return .failure(messageKey: "sync_error_generic", detail: nsError.localizedDescription)
        }
    }
}
