import SwiftUI
import UIKit

/// 英数はFigtree、和文はZen Maru Gothic——という1つの書体スタック。
///
/// FigtreeにはCJKのグリフが無い。CoreTextの既定のフォールバックに任せると
/// 和文だけシステムのゴシックに落ち、丸ゴシックの見出しと並んだときに
/// ちぐはぐになる。そこで `kCTFontCascadeListAttribute` でZen Maru Gothicを
/// 明示的に次点に置き、そこにも無いもの（絵文字・ハングルなど）だけを
/// システムの書体へ落としている。Android版 `theme/Fonts.kt` と同じ考え方。
enum PokkeFonts {

    /// フォント名は各TTFのPostScript名。Info.plist の UIAppFonts と対応する
    private enum Face {
        static let wordmark = "Caprasimo-Regular"
        static let roundedRegular = "ZenMaruGothic-Regular"
        static let roundedBold = "ZenMaruGothic-Bold"
        static let latinRegular = "Figtree-Regular"
        static let latinMedium = "Figtree-Medium"
        static let latinSemiBold = "Figtree-SemiBold"
        static let latinBold = "Figtree-Bold"
    }

    /// 本文の太さ。Zen Maru Gothic は 400 と 700 しか無いので、中間の太さはどちらかに寄せる
    enum BodyWeight {
        case regular, medium, semiBold, bold

        var latin: String {
            switch self {
            case .regular: return Face.latinRegular
            case .medium: return Face.latinMedium
            case .semiBold: return Face.latinSemiBold
            case .bold: return Face.latinBold
            }
        }

        var japanese: String {
            switch self {
            case .regular, .medium: return Face.roundedRegular
            case .semiBold, .bold: return Face.roundedBold
            }
        }
    }

    /// ワードマーク「Pokke」専用。Caprasimoは英字しか持たないので、この書体はロゴ以外に使わない
    static func wordmark(_ size: CGFloat) -> Font {
        scaled(name: Face.wordmark, fallback: nil, size: size, style: .largeTitle)
    }

    /// 見出し・ボタン・ナビラベル用の丸ゴシック。
    /// Zen Maru Gothic はラテン文字も持っているので、英語UIでも同じ丸みで揃う
    static func rounded(_ size: CGFloat, bold: Bool = true) -> Font {
        scaled(
            name: bold ? Face.roundedBold : Face.roundedRegular,
            fallback: nil,
            size: size,
            style: .headline
        )
    }

    /// 本文系。英数はFigtree、和文はZen Maru Gothicへ落ちる
    static func body(_ size: CGFloat, _ weight: BodyWeight) -> Font {
        scaled(name: weight.latin, fallback: weight.japanese, size: size, style: .body)
    }

    /// 本文用のUIFont。UIKitで組む部分（ネイティブ広告カード）から使う
    static func uiFont(_ size: CGFloat, _ weight: BodyWeight) -> UIFont {
        UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: raw(name: weight.latin, fallback: weight.japanese, size: size))
    }

    /// 組み立てたUIFontは使い回す。和文フォントは1つ約3.8MBあり、毎回作り直すと重い
    private static var cache: [String: UIFont] = [:]

    private static func raw(name: String, fallback: String?, size: CGFloat) -> UIFont {
        let key = "\(name)|\(fallback ?? "-")|\(size)"
        if let cached = cache[key] { return cached }

        var descriptor = UIFontDescriptor(fontAttributes: [.name: name])
        if let fallback {
            let cascade = [UIFontDescriptor(fontAttributes: [.name: fallback])]
            descriptor = descriptor.addingAttributes([
                UIFontDescriptor.AttributeName(rawValue: kCTFontCascadeListAttribute as String): cascade,
            ])
        }
        let uiFont = UIFont(descriptor: descriptor, size: size)
        cache[key] = uiFont
        return uiFont
    }

    private static func scaled(
        name: String,
        fallback: String?,
        size: CGFloat,
        style: UIFont.TextStyle
    ) -> Font {
        // 端末の文字サイズ設定に追従させる（Androidの sp と同じ振る舞い）
        Font(UIFontMetrics(forTextStyle: style).scaledFont(for: raw(name: name, fallback: fallback, size: size)))
    }
}

/// 画面で使う文字のスタイル。行間はデザインの倍率指定をptに直した値。
/// Android版 `pokkeTypography` と1対1で対応する。
enum PokkeType {
    /// ワードマーク
    static let display = PokkeFonts.wordmark(30)
    /// 画面タイトル（ホーム以外）
    static let headline = PokkeFonts.rounded(24)
    /// コレクション詳細の名前
    static let titleLarge = PokkeFonts.rounded(19)
    /// シートの見出し
    static let titleMedium = PokkeFonts.rounded(17)
    /// 主ボタン
    static let titleSmall = PokkeFonts.rounded(15)
    /// リストカードのタイトル
    static let bodyLarge = PokkeFonts.body(14, .bold)
    /// 本文。行間1.9倍（`bodyLineSpacing` と併せて使う）
    static let bodyMedium = PokkeFonts.body(13.5, .medium)
    /// メタ情報（ドメイン・時刻）
    static let bodySmall = PokkeFonts.body(11.5, .semiBold)
    /// 枠付きボタン・入力欄
    static let labelLarge = PokkeFonts.body(13.5, .bold)
    /// セクション見出し・チップ
    static let labelMedium = PokkeFonts.body(12.5, .bold)
    /// ナビゲーションのラベル
    static let labelSmall = PokkeFonts.rounded(10)

    /// bodyMedium の行間（25.65 - 13.5）
    static let bodyLineSpacing: CGFloat = 12
}
