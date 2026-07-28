import SwiftUI

/// アプリアイコンから採取したパレット（Pokke）。Android版の Theme.kt と同じ値。
///
/// Android版が lightColorScheme 固定なので、こちらもライト固定にして見た目を揃える
/// （RootView で preferredColorScheme(.light) を指定している）。
enum Palette {
    static let navy = Color(hex: 0x1A237E)       // Pカードの濃紺（メインカラー）
    static let royalBlue = Color(hex: 0x5B8DEF)  // アイコンの青い丸（アクセント）
    static let skyTint = Color(hex: 0xD8EDF9)    // アイコン背景の淡い青
    static let slate = Color(hex: 0x2E3A59)      // 文字用のダークスレート
    static let appBackground = Color(hex: 0xF5F9FE)
    static let placeholderBg = Color(hex: 0xE7EEF9)

    static let primary = navy
    static let onPrimary = Color.white
    static let primaryContainer = skyTint
    static let secondary = royalBlue
    static let surface = Color.white
    static let onSurface = slate
    static let surfaceVariant = placeholderBg
    static let onSurfaceVariant = Color(hex: 0x5A6480)
    static let outline = Color(hex: 0xC2CCE0)
    static let error = Color(hex: 0xB3261E)

    /// コレクションに割り当てられる色（絵文字カードの背景）
    static let collectionColors: [Color] = [
        Color(hex: 0xFFE0B2), // オレンジ
        Color(hex: 0xFFCDD2), // ピンク
        Color(hex: 0xC8E6C9), // グリーン
        Color(hex: 0xBBDEFB), // ブルー
        Color(hex: 0xE1BEE7), // パープル
        Color(hex: 0xFFF9C4), // イエロー
        Color(hex: 0xB2DFDB), // ティール
        Color(hex: 0xD7CCC8), // ブラウン
    ]

    /// 負のインデックスでも巡回する（Kotlinの Int.mod 相当）
    static func collectionColor(_ colorIndex: Int) -> Color {
        let count = collectionColors.count
        return collectionColors[((colorIndex % count) + count) % count]
    }
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

/// Material3のカードに相当する白い角丸カード
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
            )
            .shadow(color: Palette.slate.opacity(0.07), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 12, fill: Color = Palette.surface) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, fill: fill))
    }
}
