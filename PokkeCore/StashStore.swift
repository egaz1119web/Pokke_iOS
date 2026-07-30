import Foundation

/// stash.json の置き場所。
///
/// App Group のコンテナに置くことで、共有拡張（PokkeShare）が保存したリンクを
/// アプリ本体からもそのまま読める。Android では同じプロセスの filesDir で足りるが、
/// iOS の拡張は別プロセスなので共有コンテナが要る。
enum StashStore {

    static let appGroupId = "group.com.egaz.stash"

    static var fileUrl: URL {
        let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            // App Group が使えない状況（未設定のシミュレータなど）でも起動だけはできるようにする
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("stash.json")
    }

    static func read() -> StashState? {
        guard let text = try? String(contentsOf: fileUrl, encoding: .utf8) else { return nil }
        return StashJson.fromJson(text)
    }

    static func write(_ state: StashState) {
        let text = StashJson.toJson(state)
        try? text.write(to: fileUrl, atomically: true, encoding: .utf8)
    }

    /// ファイルごと消す。「データを全部削除」で使う。
    /// 空の状態を書き込むのではなく消すのは、共有拡張側が次に書くまで
    /// 何も残っていない状態にしたいため
    static func clear() {
        try? FileManager.default.removeItem(at: fileUrl)
    }
}
