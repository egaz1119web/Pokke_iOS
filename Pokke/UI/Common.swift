import SwiftUI

/// 「3日前」「3 days ago」のような相対時刻表示
func relativeTime(_ millis: EpochMillis) -> String {
    let minutes = Int((nowMillis() - millis) / 60_000)
    switch minutes {
    case ..<1:
        return L.s("time_just_now")
    case ..<60:
        return L.plural("time_minutes_ago", minutes)
    case ..<(60 * 24):
        return L.plural("time_hours_ago", minutes / 60)
    default:
        return L.plural("time_days_ago", minutes / (60 * 24))
    }
}

/// リンクを開く＋再訪カウント。
///
/// 常に端末の既定のブラウザ（またはそのURLを持つアプリ）へ渡す。
/// アプリ内の `SFSafariViewController` で開く方式も試したが、Xのように
/// アプリ側へ誘導するサービスで正しく表示できなかったため取りやめた。
@MainActor
func openLink(_ item: StashItem) {
    StashRepository.shared.markOpened(id: item.id)
    guard let url = URL(string: item.url) else { return }
    UIApplication.shared.open(url)
}

/// 他のアプリへリンクを共有する。送信先はシステムの共有シートで利用者が選ぶ
@MainActor
func shareLink(_ item: StashItem, from sourceRect: CGRect? = nil) {
    guard let url = URL(string: item.url), let presenter = topViewController() else { return }
    let activity = UIActivityViewController(activityItems: [item.title, url], applicationActivities: nil)
    // iPadでは吹き出しの根元が要る。指定が無ければ画面中央から出す
    if let popover = activity.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = sourceRect ?? CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )
        popover.permittedArrowDirections = []
    }
    presenter.present(activity, animated: true)
}

/// 今いちばん手前のビューコントローラ。シートの上にさらに出すために辿る
@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}

/// コレクションカードの地色
func collectionColor(_ colorIndex: Int) -> Color { Palette.collectionColor(colorIndex) }

/// サムネイル。OGP画像があればそれを、無ければサービス色の面に線画アイコンを置く。
///
/// 地色をサービスごとに変えているので、画像が取れていない行が並んでも
/// 一覧が単調なグレーの帯にならない。
struct Thumbnail: View {
    let item: StashItem
    var size: CGFloat = 76
    var corner: CGFloat = 16

    var body: some View {
        ZStack {
            ServiceVisual.of(host: item.host).tint
            LinkImage(item: item, logoSize: size * 0.37)
        }
        // 先に大きさを決めてから切り抜く。順番が逆だと画像がカードの外へはみ出す
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// OGP画像 → 失敗したらサービスのロゴ。
/// 画像URLが取れていても実際には404や期限切れで表示できないことがあり、
/// その場合に空白のままだと何のリンクか分からなくなるためロゴへ落とす。
struct LinkImage: View {
    let item: StashItem
    var logoSize: CGFloat
    /// 一覧のサムネイルは切り抜かず全体を見せる。Instagramの正方形画像や
    /// 横長のOGP画像を切り抜くと中央の一部しか映らず、何の画像か分からなくなる
    var fill = false

    var body: some View {
        if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    if fill {
                        // 埋める向きの拡大は枠より大きなレイアウト寸法を返すので、
                        // そのまま置くとグリッドのセルごと押し広げてしまう。
                        // overlay は親の大きさに関与しないため、はみ出しは描画だけに閉じる
                        Color.clear.overlay {
                            image.resizable().scaledToFill()
                        }
                    } else {
                        image.resizable().scaledToFit()
                    }
                case .failure:
                    logo
                default:
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            logo
        }
    }

    private var logo: some View {
        ServiceLogo(
            domain: DomainGrouping.logoDomain(host: item.host),
            label: DomainGrouping.domainLabel(host: item.host),
            size: logoSize
        )
    }
}

/// リスト1行分のアイテムカード。
///
/// ホームは大きめのサムネイル＋抜粋、コレクション詳細や検索結果は
/// 小さめのサムネイルだけ、と密度を変えて使う。
struct ItemRow: View {
    let item: StashItem
    var thumbnailSize: CGFloat = 76
    var thumbnailCorner: CGFloat = 16
    var showExcerpt = true
    let onTap: () -> Void

    var body: some View {
        PokkeCard(action: onTap) {
            HStack(spacing: 12) {
                Thumbnail(item: item, size: thumbnailSize, corner: thumbnailCorner)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(PokkeType.bodyLarge)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // SNSの投稿は本文が無いとタイトルだけでは中身が分からないので一覧にも出す
                    if showExcerpt, let description = item.description {
                        Text(description)
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral700)
                            .lineLimit(1)
                    }
                    ItemMetaRow(item: item)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// ドメイン・保存時刻と、右端の未読ドット
private struct ItemMetaRow: View {
    let item: StashItem

    var body: some View {
        HStack(spacing: 6) {
            Text(item.host)
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .lineLimit(1)
                .layoutPriority(-1)
            Text("・")
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral400)
            Text(relativeTime(item.savedAt))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if item.unread { UnreadDot() }
        }
    }
}

struct UnreadDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(Palette.ink).frame(width: size, height: size)
    }
}

/// グリッド表示用のカード。サムネイルを大きく見せる
struct ItemGridCard: View {
    let item: StashItem
    let onTap: () -> Void

    var body: some View {
        PokkeCard(padding: 9, action: onTap) {
            ZStack {
                ServiceVisual.of(host: item.host).tint
                LinkImage(item: item, logoSize: 32, fill: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text(item.title)
                .font(PokkeType.bodyLarge)
                .foregroundStyle(Palette.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 3)
                .padding(.top, 9)

            HStack(spacing: 5) {
                Text(item.host)
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .lineLimit(1)
                    .layoutPriority(-1)
                Text(relativeTime(item.savedAt))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)
            .padding(.bottom, 3)
        }
    }
}

/// 長い本文を折りたたんで表示する。あふれている場合だけ開閉リンクを出す。
///
/// 本文は長押しで選択・コピーできる。そのため本文自体はタップで開閉しない
/// （タップ領域を載せると選択のジェスチャーと取り合う）。
struct ExpandableText: View {
    let text: String
    var collapsedLineLimit = 3

    @State private var expanded = false
    @State private var overflowing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .lineLimit(expanded ? nil : collapsedLineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .background(overflowProbe)

            if overflowing {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(L.s(expanded ? "detail_show_less" : "detail_show_more"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.accent700)
                        // 文字だけだと的が小さいので、押せる範囲を縦に広げておく
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    /// 全文が畳んだ高さに収まるかを [ViewThatFits] に判定させる。
    /// 収まらなかったときだけ2番目が選ばれるので、そこで開閉リンクを出す。
    /// 一度立った印は下ろさない（開いた後に消すと「閉じる」が押せなくなる）
    @ViewBuilder
    private var overflowProbe: some View {
        if !expanded {
            ViewThatFits(in: .vertical) {
                Text(text)
                    .font(PokkeType.bodyMedium)
                    .lineSpacing(PokkeType.bodyLineSpacing)
                Color.clear.onAppear { overflowing = true }
            }
            .hidden()
        }
    }
}
