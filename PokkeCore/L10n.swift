import Foundation

/// Localizable.xcstrings 引き。
///
/// キー名は Android の `res/values/strings.xml` と揃えてあるので、
/// 文言を直す時は両OSで同じキーを探せばよい。
enum L {

    static func s(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: nil, bundle: .main)
    }

    static func s(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    /// 複数形。xcstrings の plural variations を `%lld` 経由で解決する
    static func plural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(s(key), count)
    }
}
