import SwiftUI

/// 「このサイトの表示がおかしい」を知らせる前の確認シート。
///
/// 詳細シートから常に開けるので、サムネイルが出ない場合だけでなく
/// タイトルや本文が違う場合も受け口になる。
///
/// 送る内容を一字一句そのまま見せてから、ブラウザでGoogleフォームを開く。
/// 何が送られるか分からないことが抵抗の正体なので、要約せずに出す。
/// 送信ボタンはフォーム側にあり、ここで押すのは「開く」までに留める。
struct ThumbnailReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastController

    let item: StashItem

    // 完全なURLは既定で送らない。保存したリンクは本人の興味そのもので、
    // 直す側にとっては原則不要なため、欲しい人だけが足す形にする
    @State private var includeUrl = false

    private var diagnostics: String {
        ThumbnailReport.diagnosticsOf(
            item: item,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            language: Locale.preferredLanguages.first ?? Locale.current.identifier
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHandle()

                Text(L.s("report_thumbnail_title"))
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(Palette.ink)

                Text(L.s("report_thumbnail_description", item.host))
                    .font(PokkeType.bodyMedium)
                    .foregroundStyle(Palette.neutral800)
                    .padding(.top, 8)

                Text(L.s("report_thumbnail_payload_label"))
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.neutral700)
                    .padding(.top, 16)

                // 等幅で出す。診断情報は行ごとに読むものなので、字送りが揃っている方が追いやすい
                VStack(alignment: .leading, spacing: 8) {
                    Text(diagnostics)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.neutral800)
                    if includeUrl {
                        Text(item.url)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.accent800)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Corner.medium, style: .continuous).fill(Palette.neutral200))
                .padding(.top, 8)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.s("report_thumbnail_include_url"))
                            .font(PokkeType.bodyLarge)
                            .foregroundStyle(Palette.ink)
                        Text(L.s("report_thumbnail_include_url_description"))
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral600)
                    }
                    Spacer(minLength: 0)
                    PokkeSwitch(
                        isOn: $includeUrl,
                        accessibilityLabel: L.s("report_thumbnail_include_url")
                    )
                }
                .padding(.top, 14)

                Text(L.s("report_thumbnail_form_note"))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .padding(.top, 16)

                PrimaryButton(
                    title: L.s("report_thumbnail_open_form"),
                    icon: Lucide.externalLink,
                    action: openForm
                )
                .padding(.top, 12)

                Spacer(minLength: 26)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .presentationDetents([.fraction(0.82)])
        // 開けなかったことを知らせるトーストは、このシートの上に重ねないと見えない
        .toastOverlay(toast)
    }

    // 「アプリ内で開く」設定には従わず、常に外部ブラウザへ渡す。
    // URLバーに docs.google.com が出た状態で送信できることが、
    // アプリが裏で何か送っているのではないという裏取りになる
    private func openForm() {
        let url = ThumbnailReport.prefillUrl(
            host: item.host,
            diagnostics: diagnostics,
            fullUrl: includeUrl ? item.url : nil
        )
        guard let target = URL(string: url) else {
            toast.show(L.s("report_thumbnail_open_failed"))
            return
        }
        // ブラウザが無い等で開けなかったときに黙って閉じると、送れたのかどうか分からないまま終わってしまう
        UIApplication.shared.open(target) { opened in
            if opened {
                dismiss()
            } else {
                toast.show(L.s("report_thumbnail_open_failed"))
            }
        }
    }
}
