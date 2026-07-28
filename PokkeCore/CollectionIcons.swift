import Foundation

/// コレクションに選べる線画アイコンの識別子。
///
/// 実際の絵はUI層（`Lucide.collectionIcon`）で解決する。ここに置いてあるのは
/// 永続化とマージのために必要な「文字列としての識別子」だけ。
/// Android版 `data/CollectionIcons.kt` と同じ並び・同じ変換規則であること。
enum CollectionIcons {

    /// 作成ダイアログに並ぶ12種。並び順がそのまま6列×2行になる
    static let all = [
        "bookmark", "utensils", "gamepad", "bulb", "headphones", "plane",
        "bag", "clap", "briefcase", "paw", "star", "heart",
    ]

    static let `default` = all[0]

    /// 絵文字で保存されていた頃のデータを線画アイコンへ読み替える。
    ///
    /// 旧「🏃」だけは対応する絵が無いので既定に落とす。
    /// 未知の値（他端末が先に新しいアイコンを使った場合など）も既定に落として、
    /// 何も描けない状態にはしない。
    static func fromLegacyEmoji(_ emoji: String) -> String {
        switch emoji {
        case "📚": return "bookmark"
        case "🍳": return "utensils"
        case "🎮": return "gamepad"
        case "💡": return "bulb"
        case "🎧": return "headphones"
        case "✈️": return "plane"
        case "🛍️": return "bag"
        case "🎬": return "clap"
        case "💼": return "briefcase"
        case "🐈": return "paw"
        case "⭐": return "star"
        default: return `default`
        }
    }

    /// 保存されている値が今のアイコン集合に無ければ既定へ丸める
    static func normalize(_ icon: String) -> String {
        all.contains(icon) ? icon : `default`
    }
}
