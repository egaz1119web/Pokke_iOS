import SwiftUI

/// サービスの見え方。サムネイルが無いときの地色と線画アイコンを決める。
///
/// 主要3サービスだけ専用の色を持たせ、それ以外はWeb（テラコッタの淡色＋地球儀）に寄せる。
/// 一覧に並んだとき、色だけで「Instagramの束」「YouTubeの束」が見分けられるのが狙い。
enum ServiceVisual {
    case instagram, x, youTube, web

    var tint: Color {
        switch self {
        case .instagram: return Palette.accent2_100
        case .x: return Palette.neutral200
        case .youTube: return Palette.accent200
        case .web: return Palette.accent100
        }
    }

    var foreground: Color {
        switch self {
        case .instagram: return Palette.accent2_700
        case .x: return Palette.neutral800
        case .youTube: return Palette.accent800
        case .web: return Palette.accent700
        }
    }

    var icon: Lucide.Icon {
        switch self {
        case .instagram: return Lucide.instagram
        case .x: return Lucide.xLogo
        case .youTube: return Lucide.play
        case .web: return Lucide.globe
        }
    }

    /// ホスト名から見え方を決める。[DomainGrouping] の表示名に合わせてある
    static func of(host: String) -> ServiceVisual {
        ofLabel(DomainGrouping.domainLabel(host: host))
    }

    static func ofLabel(_ label: String) -> ServiceVisual {
        switch label {
        case "Instagram": return .instagram
        // 表示名は歴史的に Twitter のまま。アイコンは X の「×」
        case "Twitter": return .x
        case "YouTube": return .youTube
        default: return .web
        }
    }
}

/// サービスのロゴ。
///
/// 1. logo.dev（トークンが設定されていれば）
/// 2. Googleのファビコンサービス
/// 3. [ServiceVisual] の線画アイコン
///
/// の順にフォールバックする。ロゴ取得のためにドメイン名を外部サービスへ送るので、
/// プライバシーポリシーにもその旨を書いてある。
///
/// 通信が要らない線画だけで済ませることもできるが、GitHubやnoteのように
/// 専用アイコンを持たないサービスは全部が同じ地球儀になってしまうため、
/// 取れるならブランドのファビコンを優先している。
struct ServiceLogo: View {
    let domain: String
    let label: String
    var size: CGFloat = 20
    var tint: Color?

    /// 失敗するたびに次の候補へ進む
    @State private var attempt = 0

    var body: some View {
        Group {
            if let url = Self.logoUrl(domain: domain, attempt: attempt) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        fallbackIcon.onAppear { attempt += 1 }
                    default:
                        // 読み込み中は空。線画を出すとロゴ確定時にちらつく
                        Color.clear
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            } else {
                fallbackIcon
            }
        }
        .id(domain)
    }

    private var fallbackIcon: some View {
        LucideIconView(
            icon: ServiceVisual.ofLabel(label).icon,
            size: size,
            color: tint ?? ServiceVisual.ofLabel(label).foreground
        )
    }

    /// attempt 番目のロゴURL。候補が尽きたら nil（＝線画アイコンで表示）
    private static func logoUrl(domain: String, attempt: Int) -> URL? {
        guard !domain.isEmpty else { return nil }
        var candidates: [String] = []
        if !logoDevToken.isEmpty {
            candidates.append("https://img.logo.dev/\(domain)?token=\(logoDevToken)&size=64&format=png")
        }
        candidates.append("https://www.google.com/s2/favicons?domain=\(domain)&sz=64")
        guard attempt < candidates.count else { return nil }
        return URL(string: candidates[attempt])
    }

    /// logo.dev の publishable token。Android版は local.properties から埋め込むが、
    /// iOSは Info.plist の `LogoDevToken` を見る。未設定ならGoogleのファビコンに落ちる
    private static let logoDevToken: String =
        Bundle.main.object(forInfoDictionaryKey: "LogoDevToken") as? String ?? ""
}
