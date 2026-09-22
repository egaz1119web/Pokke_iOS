import FirebaseAnalytics
import Foundation

/// Firebase SDKを共有ターゲットへ漏らさず、AppAnalyticsのイベントだけ本体から送る。
@MainActor
enum FirebaseAnalyticsBridge {
    static func install() {
        AppAnalytics.install { name, strings, integers in
            var parameters: [String: Any] = strings
            integers.forEach { parameters[$0.key] = NSNumber(value: $0.value) }
            Analytics.logEvent(name, parameters: parameters)
        }
    }
}
