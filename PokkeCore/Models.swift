import Foundation

/// エポックからのミリ秒。Android版とJSONを共有するため、時刻はすべてこの単位で持つ
typealias EpochMillis = Int64

extension Date {
    var epochMillis: EpochMillis { EpochMillis((timeIntervalSince1970 * 1000).rounded()) }
    init(epochMillis: EpochMillis) { self.init(timeIntervalSince1970: Double(epochMillis) / 1000) }
}

func nowMillis() -> EpochMillis { Date().epochMillis }

/// 保存された1件のリンク
struct StashItem: Identifiable, Equatable, Hashable {
    var id: String
    var url: String
    var title: String
    var siteName: String?
    var imageUrl: String?
    /// og:description。SNSの投稿では本文がここに入るため、詳細画面で見せる。
    /// 記事の場合はリード文・要約になる。
    var description: String?
    var collectionId: String?
    var tags: [String] = []
    var savedAt: EpochMillis
    var archived: Bool = false
    /// ずっと手元に残しておきたい印。
    ///
    /// アーカイブ（読み終えて片付けた）とは別の軸で、どちらの状態でも立てられる。
    /// 立っているものは古いリンクの一括整理（`OldItems`）の対象から外れる。
    var favorite: Bool = false
    var openCount: Int = 0
    var lastOpenedAt: EpochMillis?
    /// リマインダーの通知時刻。設定していなければ nil。
    ///
    /// 予約そのもの（`ReminderScheduler`）は端末ごとの話なので、ここには時刻だけ置く
    var remindAt: EpochMillis?
    /// 端末間マージの勝敗判定に使う最終更新時刻。既存データは savedAt を初期値とする
    var updatedAt: EpochMillis

    init(
        id: String,
        url: String,
        title: String,
        siteName: String? = nil,
        imageUrl: String? = nil,
        description: String? = nil,
        collectionId: String? = nil,
        tags: [String] = [],
        savedAt: EpochMillis,
        archived: Bool = false,
        favorite: Bool = false,
        openCount: Int = 0,
        lastOpenedAt: EpochMillis? = nil,
        remindAt: EpochMillis? = nil,
        updatedAt: EpochMillis? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.siteName = siteName
        self.imageUrl = imageUrl
        self.description = description
        self.collectionId = collectionId
        self.tags = tags
        self.savedAt = savedAt
        self.archived = archived
        self.favorite = favorite
        self.openCount = openCount
        self.lastOpenedAt = lastOpenedAt
        self.remindAt = remindAt
        self.updatedAt = updatedAt ?? savedAt
    }

    var unread: Bool { !archived && openCount == 0 }

    /// 表示用のホスト名。URLとして解釈できなければURLそのものを返す
    var host: String {
        guard let host = URLComponents(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// アイコン＋色でカスタムできるコレクション
struct StashCollection: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    /// 線画アイコンの識別子（"bookmark" など）。UI側で絵に解決する。
    /// 絵文字を持っていた頃のデータは読み込み時にここへ変換される。
    var icon: String
    var colorIndex: Int
    /// 端末間マージの勝敗判定に使う最終更新時刻
    var updatedAt: EpochMillis = 0
}

/// Weekly Meter用の利用イベント。type = "save" | "open"
struct UsageEvent: Equatable, Hashable {
    static let save = "save"
    static let open = "open"

    var type: String
    var time: EpochMillis
}

/// アプリ全体の永続化対象の状態
struct StashState: Equatable {
    var items: [StashItem] = []
    var collections: [StashCollection] = []
    var events: [UsageEvent] = []
    /// Today's Pickを最後に選んだ日 (yyyy-MM-dd)
    var pickDate: String = ""
    /// 今日スキップしたアイテムID
    var pickSkippedIds: [String] = []
    /// 削除済みID → 削除時刻の墓標。
    /// これが無いと、別端末に残っている削除前のレコードがマージで復活してしまう。
    var deletedIds: [String: EpochMillis] = [:]
}
