import Foundation

/// StashState <-> JSON の相互変換。ファイル永続化とFirestore同期に使う。
///
/// Android版 (`com.egaz.stash.data.StashJson`) と**完全に同じスキーマ**であること。
/// 同じFirestoreドキュメントを両OSで読み書きするので、キー名・型・時刻の単位
/// （エポックミリ秒）を変えると相互運用が壊れる。
enum StashJson {

    static func toJson(_ state: StashState) -> String {
        var root: [String: Any] = [:]
        root["items"] = state.items.map(itemToJson)
        root["collections"] = state.collections.map { c -> [String: Any] in
            [
                "id": c.id,
                "name": c.name,
                "icon": c.icon,
                "colorIndex": c.colorIndex,
                "updatedAt": c.updatedAt,
            ]
        }
        root["events"] = state.events.map { ["type": $0.type, "time": $0.time] as [String: Any] }
        root["pickDate"] = state.pickDate
        root["pickSkippedIds"] = state.pickSkippedIds
        root["deletedIds"] = state.deletedIds.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    static func fromJson(_ text: String) -> StashState? {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let items = (root["items"] as? [[String: Any]] ?? []).compactMap(itemFromJson)
        let collections = (root["collections"] as? [[String: Any]] ?? []).compactMap { o -> StashCollection? in
            guard let id = o["id"] as? String, let name = o["name"] as? String else { return nil }
            return StashCollection(
                id: id,
                name: name,
                // 線画アイコンに移行する前は絵文字を持っていた
                icon: (o["icon"] as? String)
                    ?? CollectionIcons.fromLegacyEmoji(o["emoji"] as? String ?? ""),
                colorIndex: millis(o["colorIndex"]).map(Int.init) ?? 0,
                updatedAt: millis(o["updatedAt"]) ?? 0
            )
        }
        let events = (root["events"] as? [[String: Any]] ?? []).compactMap { o -> UsageEvent? in
            guard let type = o["type"] as? String, let time = millis(o["time"]) else { return nil }
            return UsageEvent(type: type, time: time)
        }
        let deleted = (root["deletedIds"] as? [String: Any] ?? [:])
            .compactMapValues { millis($0) }

        return StashState(
            items: items,
            collections: collections,
            events: events,
            pickDate: root["pickDate"] as? String ?? "",
            pickSkippedIds: root["pickSkippedIds"] as? [String] ?? [],
            deletedIds: deleted
        )
    }

    private static func itemToJson(_ item: StashItem) -> [String: Any] {
        [
            "id": item.id,
            "url": item.url,
            "title": item.title,
            "siteName": item.siteName ?? NSNull(),
            "imageUrl": item.imageUrl ?? NSNull(),
            "description": item.description ?? NSNull(),
            "collectionId": item.collectionId ?? NSNull(),
            "tags": item.tags,
            "savedAt": item.savedAt,
            "archived": item.archived,
            "favorite": item.favorite,
            "openCount": item.openCount,
            "lastOpenedAt": item.lastOpenedAt ?? NSNull(),
            "remindAt": item.remindAt ?? NSNull(),
            "updatedAt": item.updatedAt,
        ]
    }

    private static func itemFromJson(_ o: [String: Any]) -> StashItem? {
        guard let id = o["id"] as? String,
              let url = o["url"] as? String,
              let title = o["title"] as? String,
              let savedAt = millis(o["savedAt"])
        else { return nil }
        return StashItem(
            id: id,
            url: url,
            title: title,
            siteName: o["siteName"] as? String,
            imageUrl: o["imageUrl"] as? String,
            // description 導入前のデータには存在しないキー
            description: o["description"] as? String,
            collectionId: o["collectionId"] as? String,
            tags: o["tags"] as? [String] ?? [],
            savedAt: savedAt,
            archived: o["archived"] as? Bool ?? false,
            // お気に入り導入前・Android版が書いたデータにはキー自体が無い
            favorite: o["favorite"] as? Bool ?? false,
            openCount: millis(o["openCount"]).map(Int.init) ?? 0,
            lastOpenedAt: millis(o["lastOpenedAt"]),
            // リマインダー導入前・Android版が書いたデータにはキー自体が無い
            remindAt: millis(o["remindAt"]),
            // updatedAt 導入前に保存されたデータは savedAt を最終更新時刻とみなす
            updatedAt: millis(o["updatedAt"]) ?? savedAt
        )
    }

    /// JSONSerialization は数値を NSNumber で返す。Bool と混ざらないよう明示的に取り出す
    private static func millis(_ value: Any?) -> EpochMillis? {
        guard let number = value as? NSNumber, !(value is Bool) else { return nil }
        return number.int64Value
    }
}
