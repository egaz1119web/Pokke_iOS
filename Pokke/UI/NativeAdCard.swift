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
            rootViewController: GoogleAuth.rootViewController(),
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
                    .cardBackground()
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
private struct NativeAdViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.translatesAutoresizingMaskIntoConstraints = false

        let badge = UILabel()
        badge.text = "Ad"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(Palette.royalBlue)
        badge.layer.cornerRadius = 3
        badge.layer.masksToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 15),
        ])

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        // メイン画像/動画アセット。AdMobのネイティブ広告バリデータは、ここをImageViewで
        // 代用せずMediaViewを使うことを必須にしている（審査・広告配信ポリシー上の要件）
        let media = MediaView()
        media.clipsToBounds = true
        media.layer.cornerRadius = 12
        media.translatesAutoresizingMaskIntoConstraints = false
        let mediaHeight = media.heightAnchor.constraint(equalToConstant: 160)
        mediaHeight.priority = .required

        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .subheadline)
        headline.numberOfLines = 2
        headline.textColor = UIColor(Palette.onSurface)

        let advertiser = UILabel()
        advertiser.font = .preferredFont(forTextStyle: .caption1)
        advertiser.textColor = UIColor(Palette.onSurfaceVariant)

        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .caption1)
        body.numberOfLines = 2
        body.textColor = UIColor(Palette.onSurfaceVariant)

        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.baseBackgroundColor = UIColor(Palette.primary)
        ctaConfig.baseForegroundColor = UIColor(Palette.onPrimary)
        ctaConfig.cornerStyle = .medium
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
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

        let topRow = UIStackView(arrangedSubviews: [icon, textColumn, cta])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center

        // 上段(アイコン・見出し・CTA) → メイン画像/動画 → 本文、の縦積み
        let column = UIStackView(arrangedSubviews: [topRow, media, body])
        column.axis = .vertical
        column.spacing = 10
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

    /// UIViewRepresentableはAuto Layout制約だけでは`List`の行の高さに正しく反映されないことがある
    /// （制約は組めていても、SwiftUI側がそれを読み取れず既定の小さいサイズのまま次の行と重なる）。
    /// 明示的にAuto Layoutで計算した高さを返し、`List`に正しい行高を伝える。
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

        (adView.mediaView as? MediaView)?.mediaContent = nativeAd.mediaContent

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
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                ]))
            }
        }
        adView.callToActionView?.isHidden = nativeAd.callToAction == nil

        adView.nativeAd = nativeAd
    }
}
