import GoogleMobileAds
import SwiftUI
import UIKit

/// 広告ユニットID。
///
/// DEBUG では Google公式のテストIDを使う。本番IDを開発中に叩くと「無効なトラフィック」で
/// AdMobアカウントが停止され得るため、ここは絶対に切り替えを外さないこと（Android版と同じ方針）。
enum AdUnits {
    #if DEBUG
    static let native = "ca-app-pub-3940256099942544/3986624511"
    #else
    static let native = "ca-app-pub-9758850573913500/1496589070"
    #endif
}

/// ネイティブ広告を1件ロードして保持する。同意が取れるまではリクエストしない。
@MainActor
final class NativeAdLoader: NSObject, ObservableObject, NativeAdLoaderDelegate {

    @Published private(set) var nativeAd: NativeAd?

    private var adLoader: AdLoader?

    func load(adUnitId: String) {
        guard nativeAd == nil, adLoader == nil else { return }
        let loader = AdLoader(
            adUnitID: adUnitId,
            rootViewController: AuthService.rootViewController(),
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.nativeAd = nativeAd }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("[NativeAd] 読み込み失敗: \(error.localizedDescription)")
    }
}

/// リンク行に馴染む見た目でネイティブ広告を表示するカード。
/// 同意前・ロード前・失敗時は何も描かない（リストに隙間を作らない）。
struct NativeAdCard: View {
    @StateObject private var loader = NativeAdLoader()
    @ObservedObject private var consent = AdsConsent.shared

    var body: some View {
        Group {
            if let ad = loader.nativeAd {
                NativeAdViewRepresentable(nativeAd: ad)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Corner.large, style: .continuous)
                            .fill(Palette.surface)
                    )
                    .softShadow(.sm)
            }
        }
        .onAppear { loadIfAllowed() }
        // 同意フォームは起動直後に出るので、後から解禁されるケースを拾う
        .onChange(of: consent.canRequestAds) { _, _ in loadIfAllowed() }
    }

    private func loadIfAllowed() {
        guard consent.canRequestAds else { return }
        loader.load(adUnitId: AdUnits.native)
    }
}

/// GoogleMobileAds の NativeAdView をコードで組み立てる。
/// アセットの各Viewは NativeAdView 側に登録しないとインプレッションが計測されない。
///
/// レイアウトはAndroidの `res/layout/native_ad_card.xml` に合わせているが、
/// **MediaViewだけはiOS側にしか無い**。iOSのSDKに入っている広告バリデータが
/// 「メイン画像/動画にMediaViewを使っていない」を実装エラーとして出すため、
/// 画像アセットはImageViewで代用せずMediaViewで表示している。
private struct NativeAdViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        // ここで translatesAutoresizingMaskIntoConstraints を false にしないこと。
        // 外側の幅が制約として伝わらなくなり、本文ラベルが折り返さずカードの外まで伸びる
        adView.clipsToBounds = true

        let badge = PaddedLabel()
        badge.text = L.s("ad_badge")
        badge.font = PokkeFonts.uiFont(10, .bold)
        badge.textColor = UIColor(Palette.accent)
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(Palette.accent200)
        badge.layer.cornerRadius = 4
        badge.layer.masksToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 14
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
        ])

        let media = MediaView()
        media.clipsToBounds = true
        media.layer.cornerRadius = 15
        media.translatesAutoresizingMaskIntoConstraints = false
        let mediaHeight = media.heightAnchor.constraint(equalToConstant: 160)
        mediaHeight.priority = .required

        let headline = UILabel()
        headline.font = PokkeFonts.uiFont(16, .bold)
        headline.numberOfLines = 2
        headline.textColor = UIColor(Palette.ink)

        let advertiser = UILabel()
        advertiser.font = PokkeFonts.uiFont(12, .semiBold)
        advertiser.numberOfLines = 1
        advertiser.textColor = UIColor(Palette.neutral600)

        let body = UILabel()
        body.font = PokkeFonts.uiFont(13, .medium)
        body.numberOfLines = 2
        body.textColor = UIColor(Palette.neutral700)

        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.baseBackgroundColor = UIColor(Palette.accent)
        ctaConfig.baseForegroundColor = .white
        ctaConfig.cornerStyle = .capsule
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let cta = UIButton(configuration: ctaConfig)
        cta.setContentCompressionResistancePriority(.required, for: .horizontal)
        // タップは NativeAdView が横取りするので、ボタン自身は反応させない
        cta.isUserInteractionEnabled = false

        // 見出し・本文は長くなりがち。CTAを押し出さないよう、縮むのはこちら側に任せる
        for label in [headline, advertiser, body] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        let titleRow = UIStackView(arrangedSubviews: [badge, headline])
        titleRow.axis = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .center

        let textColumn = UIStackView(arrangedSubviews: [titleRow, advertiser])
        textColumn.axis = .vertical
        textColumn.spacing = 2

        let topRow = UIStackView(arrangedSubviews: [icon, textColumn])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center

        // CTAは右寄せ。UIStackViewの空スペーサーだと幅が決まらず、
        // カードからはみ出すのでコンテナに直接制約で留める
        let ctaRow = UIView()
        cta.translatesAutoresizingMaskIntoConstraints = false
        ctaRow.addSubview(cta)
        NSLayoutConstraint.activate([
            cta.trailingAnchor.constraint(equalTo: ctaRow.trailingAnchor),
            cta.topAnchor.constraint(equalTo: ctaRow.topAnchor),
            cta.bottomAnchor.constraint(equalTo: ctaRow.bottomAnchor),
            cta.leadingAnchor.constraint(greaterThanOrEqualTo: ctaRow.leadingAnchor),
        ])

        // 上段(アイコン・見出し) → メイン画像/動画 → 本文 → CTA、の縦積み
        let column = UIStackView(arrangedSubviews: [topRow, media, body, ctaRow])
        column.axis = .vertical
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
            column.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            mediaHeight,
        ])

        adView.iconView = icon
        adView.mediaView = media
        adView.headlineView = headline
        adView.advertiserView = advertiser
        adView.bodyView = body
        adView.callToActionView = cta
        return adView
    }

    /// UIViewRepresentableはAuto Layout制約だけではSwiftUI側の行の高さに正しく反映されない
    /// （制約は組めていても、SwiftUIがそれを読み取れず既定の小さいサイズのまま次の行と重なる）。
    /// 明示的にAuto Layoutで計算した高さを返す。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let size = uiView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height)
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = nativeAd.headline

        let media = adView.mediaView as? MediaView
        media?.mediaContent = nativeAd.mediaContent
        // 画像も動画も無い広告がある。枠だけ残すと白い箱が居座るので畳む
        let hasMedia = nativeAd.mediaContent.hasVideoContent || nativeAd.mediaContent.mainImage != nil
        media?.isHidden = !hasMedia

        let icon = adView.iconView as? UIImageView
        icon?.image = nativeAd.icon?.image
        icon?.isHidden = nativeAd.icon?.image == nil

        let advertiserText = nativeAd.advertiser ?? nativeAd.store
        (adView.advertiserView as? UILabel)?.text = advertiserText
        adView.advertiserView?.isHidden = advertiserText == nil

        (adView.bodyView as? UILabel)?.text = nativeAd.body
        adView.bodyView?.isHidden = nativeAd.body == nil

        if let ctaButton = adView.callToActionView as? UIButton {
            ctaButton.configuration?.attributedTitle = nativeAd.callToAction.map {
                AttributedString($0, attributes: AttributeContainer([
                    .font: PokkeFonts.uiFont(13, .bold),
                ]))
            }
        }
        adView.callToActionView?.superview?.isHidden = nativeAd.callToAction == nil

        adView.nativeAd = nativeAd
    }
}

/// 「広告」バッジ。UILabelは内側の余白を持てないので描画時に足す
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
