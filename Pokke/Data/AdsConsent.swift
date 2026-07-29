import Foundation
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// GDPR/UMP（Google User Messaging Platform）による広告の同意取得。
///
/// EEA・英国のユーザーに広告を出すには、Google認定の同意管理が AdMobポリシー上必須。
/// 同意が取れるまで（または同意不要な地域と判定されるまで）広告は読み込まない。
///
/// 同意フォーム自体の文面・出し分けは AdMob管理画面の「プライバシーとメッセージ」で設定する。
@MainActor
final class AdsConsent: ObservableObject {

    static let shared = AdsConsent()

    /// DEBUGビルドでEEA地域を強制し、同意フォームの出方を検証したい時だけ true にする。
    /// 常時 true にすると開発中の起動のたびにフォームが出るので既定はオフ
    /// （Android版も TEST_DEVICE_HASHED_IDS を入れた時だけ強制する作りになっている）。
    private static let forceEeaInDebug = false

    /// 広告を読み込んでよい状態か。falseの間は広告枠を出さない
    @Published private(set) var canRequestAds = false

    /// ユーザーがあとから同意を変更できる導線が必要（UMPの要件）。
    /// 表示が必要な地域でのみ true になる。
    @Published private(set) var isPrivacyOptionsRequired = false

    private var adsInitialized = false

    private init() {}

    /// アプリ起動時に呼ぶ。必要なら同意フォームを表示する
    func gather() {
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false

        #if DEBUG
        if Self.forceEeaInDebug {
            // シミュレータは自動でテストデバイス扱いになるので、EEAを強制すれば
            // フォームの出方をそのまま検証できる（実機で見る時は
            // コンソールに出る identifier を testDeviceIdentifiers に足す）
            let debugSettings = UMPDebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
        }
        #endif

        UMPConsentInformation.sharedInstance
            .requestConsentInfoUpdate(with: parameters) { [weak self] error in
                if let error {
                    // 取得に失敗しても、前回までの同意状態が残っていれば広告は出せる
                    print("[AdsConsent] consent info update failed: \(error.localizedDescription)")
                    self?.refresh()
                    return
                }
                guard let rootViewController = AuthService.rootViewController() else {
                    self?.refresh()
                    return
                }
                UMPConsentForm.loadAndPresentIfRequired(from: rootViewController) { formError in
                    if let formError {
                        print("[AdsConsent] consent form error: \(formError.localizedDescription)")
                    }
                    // 同意した／そもそも不要だった、いずれの場合もここで判定し直す
                    self?.refresh()
                }
            }

        // 同意が不要な地域なら、フォームの往復を待たずにすぐ初期化できる
        refresh()
    }

    /// 設定画面の「広告のプライバシー設定」から呼ぶ
    func showPrivacyOptionsForm() {
        guard let rootViewController = AuthService.rootViewController() else { return }
        UMPConsentForm.presentPrivacyOptionsForm(from: rootViewController) { [weak self] error in
            if let error {
                print("[AdsConsent] privacy options form error: \(error.localizedDescription)")
            }
            self?.refresh()
        }
    }

    private func refresh() {
        let info = UMPConsentInformation.sharedInstance
        // 広告が出ない時に、同意待ちなのか別要因なのかをここで切り分けられるようにしておく
        print("[AdsConsent] canRequestAds=\(info.canRequestAds) consentStatus=\(info.consentStatus.rawValue)")
        isPrivacyOptionsRequired = info.privacyOptionsRequirementStatus == .required

        guard info.canRequestAds else { return }
        canRequestAds = true
        // MobileAds.start は1回だけでよい
        guard !adsInitialized else { return }
        adsInitialized = true
        MobileAds.shared.start()
    }
}
