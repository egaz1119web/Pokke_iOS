import SwiftUI

/// Organicデザインシステムのトークン。Android版 `ui/theme/Theme.kt` と同じ値。
///
/// クリーム地＋テラコッタ／セージ、文字はネイビーインク。
/// 100〜900のランプは共通の明度スケールで作られているので、
/// どの色相でも同じ段は同じ明るさに見える。
///
/// 使い分け:
/// - 100〜200 … 淡い面（チップ地・サムネ地・活性ナビ地）
/// - 600〜800 … 淡い面の上に載せる文字・アイコン
/// - 押下状態 … 基準の一段濃い側（accent → accent600）
enum Palette {
    /// 画面地色（クリーム）
    static let bg = Color(hex: 0xF5EAD8)
    /// カード・シート・ナビの地
    static let surface = Color.white
    /// 見出し・カードタイトル・未読ドット・トースト地。旧ブランド紺の継承
    static let ink = Color(hex: 0x333A63)
    /// インクを使わない本文系
    static let text = Color(hex: 0x201E1D)
    /// 主ボタン・スイッチON・ナビ活性
    static let accent = Color(hex: 0xC67139)
    /// 第二アクセント（ロゴ横のしおり、Instagram系のサムネ地）
    static let accent2 = Color(hex: 0x7A8A5E)

    static let accent100 = Color(hex: 0xFFF2EB)
    static let accent200 = Color(hex: 0xFFE1D0)
    static let accent300 = Color(hex: 0xFFC6A5)
    static let accent400 = Color(hex: 0xF6A06B)
    static let accent500 = Color(hex: 0xD67F48)
    static let accent600 = Color(hex: 0xB2622D)
    static let accent700 = Color(hex: 0x8C491A)
    static let accent800 = Color(hex: 0x643312)
    static let accent900 = Color(hex: 0x402310)

    static let accent2_100 = Color(hex: 0xF0FAE1)
    static let accent2_200 = Color(hex: 0xE1EECC)
    static let accent2_300 = Color(hex: 0xCCDBB2)
    static let accent2_400 = Color(hex: 0xAEBF92)
    static let accent2_500 = Color(hex: 0x8FA073)
    static let accent2_600 = Color(hex: 0x728157)
    static let accent2_700 = Color(hex: 0x56633F)
    static let accent2_800 = Color(hex: 0x3D472B)
    static let accent2_900 = Color(hex: 0x272E1B)

    static let neutral100 = Color(hex: 0xF9F4ED)
    static let neutral200 = Color(hex: 0xEEE7DB)
    static let neutral300 = Color(hex: 0xDCD3C4)
    static let neutral400 = Color(hex: 0xC0B6A5)
    static let neutral500 = Color(hex: 0xA19786)
    static let neutral600 = Color(hex: 0x82796A)
    static let neutral700 = Color(hex: 0x645C50)
    static let neutral800 = Color(hex: 0x474238)
    static let neutral900 = Color(hex: 0x2E2B25)

    /// カードやチップの細い枠。インクの13%透過
    static let hairline = ink.opacity(0.13)
    /// 区切り線。枠よりさらに薄い
    static let divider = ink.opacity(0.08)

    /// 削除など後戻りできない操作の色。赤ではなくパレット内の濃いテラコッタ
    static let danger = accent800

    /// コレクションカードの地色。淡い面なので、上に載せる文字はインクのままで読める。
    ///
    /// colorIndex はこの並びの位置そのもの。**足すときは必ず末尾へ**。
    /// 途中に挟むと、既に作られているコレクションの色がいっせいに別の色へずれる。
    /// 選択欄は [collectionColorColumns] 列で並べるので、件数はその倍数のままにしておくこと。
    ///
    /// 既存データの colorIndex は範囲外の値が入りうるので、必ず [collectionColor] 経由で丸めること。
    static let collectionColors: [Color] = [
        // 1段目: 最初からある6色。並び順は変えない
        accent100, accent200, accent2_100, accent2_200, neutral200, neutral300,
        // 2段目: 赤〜黄
        CollectionTints.rose, CollectionTints.cherry, CollectionTints.coral,
        CollectionTints.clay, CollectionTints.amber, CollectionTints.butter,
        // 3段目: 緑〜紫
        CollectionTints.mint, CollectionTints.teal, CollectionTints.sky,
        CollectionTints.denim, CollectionTints.lilac, CollectionTints.orchid,
    ]

    /// 色の選択欄の列数。[collectionColors] はこの倍数で持つ
    static let collectionColorColumns = 6

    /// 負のインデックスでも巡回する（Kotlinの Int.mod 相当）
    static func collectionColor(_ colorIndex: Int) -> Color {
        let count = collectionColors.count
        return collectionColors[((colorIndex % count) + count) % count]
    }
}

/// コレクション専用の淡い色。
///
/// ランプの100〜200と同じ明るさに揃えてあるので、どれを選んでも上の文字は
/// そのまま読める。彩度は上げすぎない — クリーム地の上で1枚だけ浮くと、
/// 一覧が「色の見本帳」になってしまう。
private enum CollectionTints {
    static let rose = Color(hex: 0xF8D9DE)
    static let cherry = Color(hex: 0xF2C4CB)
    static let coral = Color(hex: 0xFBD0C4)
    static let clay = Color(hex: 0xEFC5B0)
    static let amber = Color(hex: 0xFBE4BC)
    static let butter = Color(hex: 0xF5EFBB)
    static let mint = Color(hex: 0xCDE9D7)
    static let teal = Color(hex: 0xC3E4E3)
    static let sky = Color(hex: 0xD3E5F3)
    static let denim = Color(hex: 0xC8D8F0)
    static let lilac = Color(hex: 0xE1DBF3)
    static let orchid = Color(hex: 0xEFD5E7)
}

/// 影。デザイントークンの shadow-sm / md / lg。
///
/// SwiftUIの既定の影は黒でコントラストが強すぎるため、
/// 地色に合わせた暖かいグレー（neutral-900）で落としている。
enum Elevation {
    case sm, md, lg

    var radius: CGFloat {
        switch self {
        case .sm: return 2
        case .md: return 6
        case .lg: return 18
        }
    }

    var y: CGFloat {
        switch self {
        case .sm: return 1
        case .md: return 3
        case .lg: return 8
        }
    }

    var opacity: Double {
        switch self {
        case .sm: return 0.10
        case .md: return 0.16
        case .lg: return 0.22
        }
    }
}

/// 角丸。小さいコントロールはすべてピル（`Capsule`）にする
enum Corner {
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 14
    static let medium: CGFloat = 18
    static let large: CGFloat = 22
    static let extraLarge: CGFloat = 26
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// デザイントークンの影
    func softShadow(_ elevation: Elevation) -> some View {
        shadow(
            color: Palette.neutral900.opacity(elevation.opacity),
            radius: elevation.radius,
            x: 0,
            y: elevation.y
        )
    }
}
