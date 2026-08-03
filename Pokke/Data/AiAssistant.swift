import FoundationModels
import Foundation

/// 端末内AI（Apple Foundation Models）が使えるかの理由。
///
/// Androidの `AiFailure.UNSUPPORTED` 相当だが、iOSでは3つに分かれる。
/// Androidと違い、アプリ側からモデルをダウンロードさせる仕組みは無い
/// （Apple Intelligence自体をOS設定で有効にした際にOSが用意する）ため、
/// 「取得中」の進捗を見せるUIは存在しない。
enum AiAvailability: Equatable {
    /// 使える
    case available
    /// この端末はApple Intelligence非対応。恒久的なので入口ごと隠す
    case deviceNotEligible
    /// 端末は対応しているが、設定でApple Intelligenceが有効になっていない
    case appleIntelligenceNotEnabled
    /// モデルの準備がまだ済んでいない（一時的。少し待てば使える）
    case modelNotReady
    /// iOS26未満
    case unsupportedOSVersion
}

enum AiFailure: Equatable {
    case unavailable(AiAvailability)
    case generationFailed
}

struct AiError: Error {
    let failure: AiFailure
}

/// 生成中にシートへ届くもの。Foundation Modelsのストリーミングは
/// **累積スナップショット**（差分ではない）なので、届いた文字列でそのまま置き換える
enum AiProgress {
    case chunk(String)
}

/// 端末内AIが使えるかの判定。
///
/// SDKに触れるのはこのファイル（と `AiSession`）だけ。
///
/// **OSの申告だけを信じてはいけない**。`SystemLanguageModel.default.availability` が
/// `.available` を返してもモデルの実体が無く、実際に生成させると
/// `ModelManagerError 1026` で必ず失敗する端末がある（Apple Intelligenceを
/// 有効にしていない実機やシミュレータで確認）。押しても必ず失敗する入口を
/// 出さないために、申告が通ったあと**短い生成を1回試して**から使えると判断する。
///
/// 使えると分かるまでは入口を出さない（出してから消えるより、少し遅れて現れる方が
/// 混乱が小さい）。**使えなかった結果は覚え込まない** — 設定でApple Intelligenceを
/// 有効にした直後や、モデルの用意が終わる前に一度試したときに、
/// アプリを再起動するまでAIが消えたままになってしまうため。
/// 端末やOSの都合で待っても変わらないもの（`deviceNotEligible` /
/// `unsupportedOSVersion`）だけは、一度で打ち切って聞き直さない。
@MainActor
final class AiAssistant: ObservableObject {

    static let shared = AiAssistant()

    /// 試し撃ちが済むまでは「準備中」＝入口を出さない
    @Published private(set) var availability: AiAvailability = .modelNotReady

    /// 使えなかったときに、次に確かめ直すまで空ける間隔。
    /// 画面を行き来するたびに試し撃ちが走らないよう、少しだけ置く
    private static let retryInterval: TimeInterval = 10

    private var probing = false
    /// 待っても変わらない理由で確定した
    private var settled = false
    private var lastProbeAt: Date?

    private init() {}

    /// 使えるかを確かめる。すでに使えると分かっているとき・確かめた直後・
    /// 待っても変わらないと分かったときは何もしない
    func probeIfNeeded() async {
        guard !probing, !settled, availability != .available else { return }
        if let lastProbeAt, Date().timeIntervalSince(lastProbeAt) < Self.retryInterval { return }
        await probe()
    }

    /// 間隔を置かずに確かめ直す。設定アプリでApple Intelligenceを入れて戻ってきた
    /// 直後のように、状況が変わっていそうなときに呼ぶ
    func recheck() async {
        guard !probing, !settled, availability != .available else { return }
        await probe()
    }

    private func probe() async {
        probing = true
        lastProbeAt = Date()
        defer { probing = false }

        switch Self.declaredAvailability() {
        case .deviceNotEligible:
            // この端末がApple Intelligenceに対応していない。待っても変わらない
            availability = .deviceNotEligible
            settled = true
        case .unsupportedOSVersion:
            availability = .unsupportedOSVersion
            settled = true
        case .appleIntelligenceNotEnabled:
            // 設定で有効にすれば使える。次の機会にまた確かめる
            availability = .appleIntelligenceNotEnabled
        case .modelNotReady:
            availability = .modelNotReady
        case .available:
            guard #available(iOS 26.0, *) else {
                availability = .unsupportedOSVersion
                settled = true
                return
            }
            availability = await Self.canActuallyGenerate() ? .available : .modelNotReady
        }
        log("端末内AIの判定: \(availability)")
    }

    /// OS・端末が申告する可否
    private static func declaredAvailability() -> AiAvailability {
        guard #available(iOS 26.0, *) else { return .unsupportedOSVersion }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            // 将来追加されるかもしれない理由。恒久扱いにはせず、待てば直る可能性を残す
            return .modelNotReady
        }
    }

    /// ごく短い生成を1回通してみる。モデルの実体が無ければここで落ちる
    @available(iOS 26.0, *)
    private static func canActuallyGenerate() async -> Bool {
        do {
            let session = LanguageModelSession()
            _ = try await session.respond(
                to: "ok",
                options: GenerationOptions(maximumResponseTokens: 1)
            )
            return true
        } catch {
            log("端末内AIの試し撃ちに失敗した（入口は出さない）", error)
            return false
        }
    }
}

/// タグ提案の構造化出力。既存タグ語彙の再利用を優先させるプロンプトと組み合わせる
@available(iOS 26.0, *)
@Generable
struct TagSuggestions {
    @Guide(description: "Up to 4 short tags for this link. Lowercase, 1-2 words each, no hashtag symbol.", .count(0...4))
    let tags: [String]
}

/// 1回のシート表示ぶんの推論エンジン。
///
/// エンジンの確保はそれなりに重いので、シートを開いている間は使い回し、
/// 閉じるときに `close()` で必ず解放する。
@available(iOS 26.0, *)
final class AiSession {

    private var session: LanguageModelSession?

    private func engine() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession()
        session = created
        return created
    }

    /// 質問を投げ、生成された文字列を届いた順（累積スナップショット）に流す
    func ask(prompt: String) -> AsyncThrowingStream<AiProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let options = GenerationOptions(temperature: 0.2)
                    let stream = engine().streamResponse(to: prompt, options: options)
                    for try await partial in stream {
                        continuation.yield(.chunk(partial.content))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    log("生成に失敗した", error)
                    continuation.finish(throwing: AiError(failure: .generationFailed))
                }
            }
        }
    }

    /// タグ候補を構造化出力で受け取る
    func suggestTags(prompt: String) async throws -> [String] {
        let options = GenerationOptions(temperature: 0.2)
        do {
            let response = try await engine().respond(to: prompt, generating: TagSuggestions.self, options: options)
            return response.content.tags
        } catch {
            log("タグの提案に失敗した", error)
            throw AiError(failure: .generationFailed)
        }
    }

    func close() {
        session = nil
    }
}

/// 端末内AIのつまずきを追うためのログ。
/// `xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "PokkeAi"'`
/// または Console.app で "PokkeAi" を絞り込む（Android版の `adb logcat -s PokkeAi` 相当）
func log(_ message: String) {
    print("[PokkeAi] \(message)")
}

func log(_ message: String, _ error: Error) {
    print("[PokkeAi] \(message): \(error)")
}
