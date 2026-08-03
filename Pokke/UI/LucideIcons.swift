import SwiftUI

/// Lucide（https://lucide.dev / ISC License）の線画アイコン。
///
/// ライブラリとして足すと使わない千数百個まで抱えることになるので、
/// デザインで使う分だけパスデータを写している。Android版
/// `ui/icon/LucideIcons.kt` と**同じ文字列**なので、片方を直したらもう片方も直す。
/// 線幅と端の処理はデザイントークン（stroke-width 2.75 / round cap・join）に合わせてある。
///
/// 円や矩形はパスに展開済み（`a r,r 0 1,0 2r,0 …` の形が円）。
enum Lucide {

    /// デザイントークンの線幅。24ptのビューポート基準
    static let strokeWidth: CGFloat = 2.75
    static let viewport: CGFloat = 24

    struct Icon: Equatable, Hashable {
        let name: String
        let data: [String]
    }

    private static func icon(_ name: String, _ data: String...) -> Icon {
        Icon(name: name, data: data)
    }

    // MARK: - ボトムナビ

    static let house = icon(
        "House",
        "M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8",
        "M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"
    )

    static let folder = icon(
        "Folder",
        "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"
    )

    static let search = icon("Search", "M3 11a8 8 0 1 0 16 0a8 8 0 1 0-16 0", "m21 21-4.3-4.3")

    static let settings = icon(
        "Settings",
        "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z",
        "M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0"
    )

    // MARK: - ヘッダー・一覧まわり

    static let plus = icon("Plus", "M5 12h14", "M12 5v14")

    /// ワードマークの横に置くしおり
    static let bookmark = icon("Bookmark", "m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2Z")

    /// リスト表示への切り替え
    static let listView = icon(
        "ListView",
        "M8 6h13", "M8 12h13", "M8 18h13",
        // 行頭の点。長さゼロの線を round キャップで描くと丸になる
        "M3 6h.01", "M3 12h.01", "M3 18h.01"
    )

    /// グリッド表示への切り替え
    static let grid = icon(
        "Grid",
        "M3 4a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1Z",
        "M14 4a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1Z",
        "M3 15a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1Z",
        "M14 15a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1Z"
    )

    static let archive = icon(
        "Archive",
        "M3 3h18a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z",
        "M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8",
        "M10 12h4"
    )

    static let inbox = icon(
        "Inbox",
        "M22 12h-6l-2 3h-4l-2-3H2",
        "M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"
    )

    // MARK: - 詳細シートのアクション

    static let externalLink = icon(
        "ExternalLink",
        "M15 3h6v6",
        "M10 14 21 3",
        "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"
    )

    /// 箱から矢印が出る、共有（アップロード）のアイコン
    static let share = icon(
        "Share",
        "M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8",
        "m16 6-4-4-4 4",
        "M12 2v13"
    )

    static let download = icon(
        "Download",
        "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4",
        "m7 10 5 5 5-5",
        "M12 15V3"
    )

    static let trash = icon(
        "Trash",
        "M3 6h18",
        "M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6",
        "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2",
        "M10 11v6",
        "M14 11v6"
    )

    /// 画像のプレースホルダ
    static let image = icon(
        "Image",
        "M2 7a3 3 0 0 1 3-3h14a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3Z",
        "m2 15 5-5 5 5 4-4 6 6",
        "M8.5 9.5h.01"
    )

    static let refreshCw = icon(
        "RefreshCw",
        "M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8",
        "M21 3v5h-5",
        "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16",
        "M8 16H3v5"
    )

    /// 「表示がおかしいことを知らせる」の吹き出しアイコン
    static let messageSquare = icon(
        "MessageSquare",
        "M22 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2z"
    )

    /// 端末内AIの入口に使う。四芒星＋小さな輝き2つ
    static let sparkles = icon(
        "Sparkles",
        "M9.94 15.5A2 2 0 0 0 8.5 14.06l-6.14-1.58a.5.5 0 0 1 0-.96L8.5 9.94A2 2 0 0 0 9.94 8.5l1.58-6.14a.5.5 0 0 1 .96 0L14.06 8.5A2 2 0 0 0 15.5 9.94l6.14 1.58a.5.5 0 0 1 0 .96L15.5 14.06a2 2 0 0 0-1.44 1.44l-1.58 6.14a.5.5 0 0 1-.96 0Z",
        "M20 3v4",
        "M22 5h-4",
        "M4 17v2",
        "M5 18H3"
    )

    /// 質問を送るボタン
    static let arrowUp = icon("ArrowUp", "m5 12 7-7 7 7", "M12 19V5")

    static let tag = icon(
        "Tag",
        "M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z",
        "M7 7.5h.01"
    )

    static let link = icon(
        "Link",
        "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71",
        "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"
    )

    // MARK: - 汎用

    static let pencil = icon(
        "Pencil",
        "M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z",
        "m15 5 4 4"
    )

    static let check = icon("Check", "M20 6 9 17l-5-5")
    static let x = icon("X", "M18 6 6 18", "m6 6 12 12")
    static let chevronLeft = icon("ChevronLeft", "m15 18-6-6 6-6")
    static let chevronRight = icon("ChevronRight", "m9 18 6-6-6-6")
    static let chevronDown = icon("ChevronDown", "m6 9 6 6 6-6")
    static let chevronUp = icon("ChevronUp", "m18 15-6-6-6 6")

    static let bookOpen = icon(
        "BookOpen",
        "M12 7v14",
        "M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"
    )

    static let languages = icon(
        "Languages",
        "m5 8 6 6", "m4 14 6-6 2-3", "M2 5h12", "M7 2h1",
        "m22 22-5-10-5 10", "M14 18h6"
    )

    // MARK: - 同期ステータス

    static let cloud = icon("Cloud", "M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z")

    static let circleCheck = icon(
        "CircleCheck",
        "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0",
        "m9 12 2 2 4-4"
    )

    static let triangleAlert = icon(
        "TriangleAlert",
        "m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3",
        "M12 9v4",
        "M12 17h.01"
    )

    static let clock = icon("Clock", "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0", "M12 6v6l4 2")

    /// リマインダー
    static let bell = icon(
        "Bell",
        "M10.268 21a2 2 0 0 0 3.464 0",
        "M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"
    )

    // MARK: - サービス識別

    static let instagram = icon(
        "Instagram",
        "M2 7a5 5 0 0 1 5-5h10a5 5 0 0 1 5 5v10a5 5 0 0 1-5 5H7a5 5 0 0 1-5-5Z",
        "M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0",
        "M17.5 6.5h.01"
    )

    /// X（旧Twitter）。ロゴそのものではなく、2ストロークの「×」で表す
    static let xLogo = icon("XLogo", "M4 4l16 16", "M20 4L4 20")

    static let globe = icon(
        "Globe",
        "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0",
        "M12 2a14.5 14.5 0 0 0 0 20a14.5 14.5 0 0 0 0-20",
        "M2 12h20"
    )

    static let play = icon("Play", "M6 3l14 9-14 9Z")

    // MARK: - コレクションのアイコン（作成ダイアログの12種）

    static let utensils = icon(
        "Utensils",
        "M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2",
        "M7 2v20",
        "M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3Zm0 0v7"
    )

    static let gamepad = icon(
        "Gamepad",
        "M6 12h4", "M8 10v4", "M15 13h.01", "M18 11h.01",
        "M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z"
    )

    static let bulb = icon(
        "Bulb",
        "M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5",
        "M9 18h6",
        "M10 22h4"
    )

    static let headphones = icon(
        "Headphones",
        "M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3"
    )

    static let plane = icon(
        "Plane",
        "M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"
    )

    static let bag = icon(
        "Bag",
        "M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z",
        "M3 6h18",
        "M16 10a4 4 0 0 1-8 0"
    )

    static let clap = icon(
        "Clap",
        "M20.2 6 3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3Z",
        "m6.2 5.3 3.1 3.9",
        "m12.4 3.4 3.1 4",
        "M3 11h18v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"
    )

    static let briefcase = icon(
        "Briefcase",
        "M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16",
        "M2 8a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2Z"
    )

    static let paw = icon(
        "Paw",
        "M9 4a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
        "M16 8a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
        "M18 16a2 2 0 1 0 4 0a2 2 0 1 0-4 0",
        "M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z"
    )

    static let star = icon(
        "Star",
        "M11.05 2.6a1 1 0 0 1 1.9 0l1.9 4.6 4.96.4a1 1 0 0 1 .59 1.8l-3.78 3.24 1.15 4.85a1 1 0 0 1-1.54 1.12L12 16l-4.23 2.6a1 1 0 0 1-1.54-1.11l1.15-4.85-3.78-3.24a1 1 0 0 1 .59-1.8l4.96-.4Z"
    )

    static let heart = icon(
        "Heart",
        "M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"
    )

    /// コレクションのアイコン識別子を絵に解決する
    static func collectionIcon(_ icon: String) -> Icon {
        switch CollectionIcons.normalize(icon) {
        case "utensils": return utensils
        case "gamepad": return gamepad
        case "bulb": return bulb
        case "headphones": return headphones
        case "plane": return plane
        case "bag": return bag
        case "clap": return clap
        case "briefcase": return briefcase
        case "paw": return paw
        case "star": return star
        case "heart": return heart
        default: return bookmark
        }
    }
}

/// アイコン1つぶんの線画。パスは初回だけ解釈して使い回す
struct LucideIconView: View {
    let icon: Lucide.Icon
    var size: CGFloat = 20
    var color: Color = Palette.ink

    var body: some View {
        LucideShape(icon: icon)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: Lucide.strokeWidth * size / Lucide.viewport,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
    }
}

private struct LucideShape: Shape {
    let icon: Lucide.Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Lucide.viewport
        return LucidePathCache.path(for: icon)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// パス文字列の解釈は毎フレームやるには重い。アイコン名で覚えておく
private enum LucidePathCache {
    private static var cache: [String: Path] = [:]

    static func path(for icon: Lucide.Icon) -> Path {
        if let cached = cache[icon.name] { return cached }
        var combined = Path()
        for d in icon.data { combined.addPath(SVGPath.parse(d)) }
        cache[icon.name] = combined
        return combined
    }
}
