import Foundation

/// Android版と共通のイベント名・パラメータを持つ、プロダクト分析の窓口。
///
/// Firebase SDK はアプリ本体だけにリンクする。共有拡張から発生したイベントは
/// App Group の UserDefaults に一時保存し、本体の次回起動時にまとめて送る。
/// URL、タイトル、検索語、タグ名、コレクション名など利用者の内容は受け取らない。
@MainActor
enum AppAnalytics {
    typealias Sink = (_ name: String, _ strings: [String: String], _ integers: [String: Int64]) -> Void

    private struct PendingEvent: Codable {
        var name: String
        var strings: [String: String]
        var integers: [String: Int64]
    }

    private static let pendingKey = "pending_analytics_events"
    private static let maxPendingEvents = 100
    private static var sink: Sink?

    /// アプリ本体からFirebaseへの送り口を登録し、共有拡張が残したイベントも送る。
    static func install(sink newSink: @escaping Sink) {
        sink = newSink
        let pending = loadPending()
        clearPending()
        pending.forEach { newSink($0.name, $0.strings, $0.integers) }
    }

    static func screen(_ name: String) {
        emit("screen_view", strings: ["screen_name": name, "screen_class": "RootView"])
    }

    static func onboardingStarted(firstRun: Bool) {
        emit(firstRun ? "onboarding_started" : "guide_started")
    }

    static func onboardingFinished(firstRun: Bool, completed: Bool, lastStep: String) {
        let name = switch (firstRun, completed) {
        case (true, true): "onboarding_completed"
        case (true, false): "onboarding_skipped"
        case (false, true): "guide_completed"
        case (false, false): "guide_skipped"
        }
        emit(name, strings: ["last_step": lastStep])
    }

    static func bookmarkSaved(source: String, newItem: Bool, assignedToCollection: Bool) {
        emit(
            "bookmark_saved",
            strings: ["source": source, "result": newItem ? "created" : "already_saved"],
            integers: ["has_collection": assignedToCollection ? 1 : 0]
        )
    }

    static func bookmarkSaveFailed(source: String, reason: String) {
        emit("bookmark_save_failed", strings: ["source": source, "reason": reason])
    }

    static func bookmarkOpened() {
        emit(
            "select_content",
            strings: ["content_type": "bookmark", "open_mode": "external_browser"]
        )
    }

    static func bookmarksShared(count: Int) {
        emit("share", strings: ["content_type": "bookmark"], integers: ["item_count": Int64(count)])
    }

    static func bookmarksSearched(queryLength: Int, resultCount: Int, tagFiltered: Bool) {
        emit(
            "bookmark_search",
            strings: ["query_length_bucket": lengthBucket(queryLength)],
            integers: ["result_count": Int64(resultCount), "tag_filtered": tagFiltered ? 1 : 0]
        )
    }

    static func bookmarkAction(_ action: String, enabled: Bool? = nil) {
        emit(
            "bookmark_action",
            strings: ["action": action],
            integers: enabled.map { ["enabled": $0 ? 1 : 0] } ?? [:]
        )
    }

    static func bulkAction(_ action: String, count: Int) {
        emit("bulk_action", strings: ["action": action], integers: ["item_count": Int64(count)])
    }

    static func collectionAction(_ action: String) {
        emit("collection_action", strings: ["action": action])
    }

    static func signInResult(method: String, result: String) {
        emit("login", strings: ["method": method, "result": result])
    }

    private static func lengthBucket(_ length: Int) -> String {
        switch length {
        case 0: "none"
        case 1...3: "1_3"
        case 4...10: "4_10"
        case 11...30: "11_30"
        default: "31_plus"
        }
    }

    private static func emit(
        _ name: String,
        strings: [String: String] = [:],
        integers: [String: Int64] = [:]
    ) {
        if let sink {
            sink(name, strings, integers)
            return
        }

        var events = loadPending()
        events.append(PendingEvent(name: name, strings: strings, integers: integers))
        if events.count > maxPendingEvents { events.removeFirst(events.count - maxPendingEvents) }
        guard let data = try? JSONEncoder().encode(events) else { return }
        sharedDefaults.set(data, forKey: pendingKey)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: StashStore.appGroupId) ?? .standard
    }

    private static func loadPending() -> [PendingEvent] {
        guard let data = sharedDefaults.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingEvent].self, from: data)) ?? []
    }

    private static func clearPending() {
        sharedDefaults.removeObject(forKey: pendingKey)
    }
}
