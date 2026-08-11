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

    /// 数で形が変わる文に、名前などをもう1つ差し込む版。
    /// 件数が `%1$lld`、差し込みが `%2$@` の順であること
    static func plural(_ key: String, _ count: Int, _ arg: String) -> String {
        String.localizedStringWithFormat(s(key), count, arg)
    }
}
