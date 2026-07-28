import SwiftUI
import UIKit

/// 練習で共有するリンク。Pokke自身の紹介ページを使う。
/// App Store に出たらそちらのURLへ差し替えること（RELEASE.md）
private let practiceUrl = "https://play.google.com/store/apps/details?id=com.egaz.stash"

/// 初回起動の案内。Android版と同じ4枚組み。
///
/// 1枚のダイアログに手順を並べる形だと「共有シートのどこにPokkeがいるのか」が
/// 伝わらなかったため、読む→図で見る→実際に1回やる→保存された物を見る、と分けている。
/// いちど共有シートから保存するとOSが次からアプリの列の手前にPokkeを出すので、
/// 「1回やってもらう」ことには案内以上の実利がある。
struct OnboardingFlow: View {
    let onFinish: () -> Void

    @ObservedObject private var repository = StashRepository.shared

    @State private var page = 0
    /// 共有シートを開いてから保存が見つかるまでの待ち状態
    @State private var waitingForShare = false
    /// 練習を始めた時点の保存済みID。ここに無いものが増えたら「保存された」と判る
    @State private var knownIds: Set<String> = []
    @State private var savedItem: StashItem?

    private let lastPage = 3

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, screenPadding)
                    .padding(.top, 8)

                pageBody
            }
        }
        // 保存はどの経路でも拾う。練習用ボタンからでも、他のアプリの共有からでもよい
        .onChange(of: repository.state.items.count) { _, _ in
            guard waitingForShare else { return }
            if let added = repository.state.items.first(where: { !knownIds.contains($0.id) }) {
                finishPractice(with: added)
            }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        ZStack {
            PageDots(count: lastPage + 1, current: page)

            HStack {
                if page > 0 && page < lastPage {
                    CircleIconButton(
                        icon: Lucide.chevronLeft,
                        accessibilityLabel: L.s("onboarding_back")
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { page -= 1 }
                    }
                }
                Spacer(minLength: 0)
                // 最後の1枚は行き先が「終わり」しか無いので、飛ばす導線は出さない
                if page < lastPage {
                    Button(action: onFinish) {
                        Text(L.s("onboarding_skip"))
                            .font(PokkeType.labelLarge)
                            .foregroundStyle(Palette.neutral700)
                            .padding(.vertical, 8)
                            .padding(.leading, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 44)
    }

    // MARK: - 各ページ

    @ViewBuilder
    private var pageBody: some View {
        switch page {
        case 0:
            IntroPage(onNext: advance)
        case 1:
            HowToSavePage(onNext: advance)
        case 2:
            PracticePage(
                waiting: waitingForShare,
                onOpenShare: openShareSheet,
                onSkip: onFinish
            )
        default:
            DonePage(item: savedItem, onFinish: onFinish)
        }
    }

    private func advance() {
        withAnimation(.easeOut(duration: 0.2)) { page += 1 }
    }

    // MARK: - 練習

    private func openShareSheet() {
        guard let url = URL(string: practiceUrl), let presenter = topViewController() else { return }

        knownIds = Set(repository.state.items.map(\.id))
        waitingForShare = true

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPadでは吹き出しの根元が要る。画面下端の中央から出す
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { _, _, _, _ in
            Task { await pollForSavedLink() }
        }
        presenter.present(activity, animated: true)
    }

    /// 共有シートが閉じた直後はまだ拡張の書き込みが終わっていないことがある。
    /// 拡張は別プロセスで、保存されても通知は飛んでこないのでこちらから見に行く
    private func pollForSavedLink() async {
        for _ in 0..<25 {
            repository.reloadFromDisk()
            if let added = repository.state.items.first(where: { !knownIds.contains($0.id) }) {
                finishPractice(with: added)
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // 見つからないまま終わったら待機だけ解く。押し直せる状態に戻すだけで、先へは進めない
        waitingForShare = false
    }

    private func finishPractice(with item: StashItem) {
        savedItem = item
        waitingForShare = false
        withAnimation(.easeOut(duration: 0.25)) { page = lastPage }
    }
}

// MARK: - 1枚目: 何のアプリか

private struct IntroPage: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(primaryTitle: L.s("onboarding_start"), onPrimary: onNext) {
            HStack(spacing: 8) {
                Text("Pokke")
                    .font(PokkeType.display)
                    .foregroundStyle(Palette.accent)
                LucideIconView(icon: Lucide.bookmark, size: 18, color: Palette.accent2)
                    .padding(.top, 4)
            }
            .padding(.top, 24)

            Text(L.s("onboarding_intro_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(L.s("onboarding_intro_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                BulletPoint(icon: Lucide.share, textKey: "onboarding_intro_point_share")
                BulletPoint(icon: Lucide.image, textKey: "onboarding_intro_point_preview")
            }
            .padding(.top, 26)
        }
    }
}

private struct BulletPoint: View {
    let icon: Lucide.Icon
    let textKey: String

    var body: some View {
        HStack(spacing: 14) {
            IconTile(
                icon: icon,
                tint: Palette.accent100,
                foreground: Palette.accent700,
                size: 44,
                iconSize: 20
            )
            Text(L.s(textKey))
                .font(PokkeType.bodyMedium)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 2枚目: 共有シートのどこにいるか

private struct HowToSavePage: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(primaryTitle: L.s("onboarding_try_it"), onPrimary: onNext) {
            Text(L.s("onboarding_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(L.s("onboarding_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            NumberedStep(number: 1, textKey: "onboarding_share_step1")
                .padding(.top, 22)
            MockShareSheet()
                .padding(.top, 12)
            Text(L.s("onboarding_share_step1_note"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            // 1→2 のつながりを示す下向きのしるし
            LucideIconView(icon: Lucide.chevronRight, size: 16, color: Palette.accent700)
                .rotationEffect(.degrees(90))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.accent100))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            NumberedStep(number: 2, textKey: "onboarding_share_step2")
                .padding(.top, 14)
            MockAppList()
                .padding(.top, 12)

            TipBox(textKey: "onboarding_share_tip")
                .padding(.top, 16)

            HStack(alignment: .top, spacing: 8) {
                LucideIconView(icon: Lucide.check, size: 15, color: Palette.accent2_700)
                    .padding(.top, 1)
                Text(L.s("onboarding_step3"))
                    .font(PokkeType.bodyMedium)
                    .foregroundStyle(Palette.neutral800)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let textKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Palette.accent)
                Text("\(number)")
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Color.white)
            }
            .frame(width: 26, height: 26)

            Text(L.s(textKey))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }
}

private struct TipBox: View {
    let textKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIconView(icon: Lucide.bulb, size: 17, color: Palette.accent700)
                .padding(.top, 1)
            Text(L.s(textKey))
                .font(PokkeType.bodySmall)
                .lineSpacing(5)
                .foregroundStyle(Palette.accent800)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                .fill(Palette.accent100)
        )
    }
}

// MARK: - 共有シートの図

/// iOSの共有シートを模した図。実物と同じく、明るいシートに
/// リンクの見出し・アプリの列・右端の「その他」が並ぶ
private struct MockShareSheet: View {
    var body: some View {
        MockSheet {
            HStack(spacing: 10) {
                IconTile(
                    icon: Lucide.link,
                    tint: Palette.neutral200,
                    foreground: Palette.neutral700,
                    size: 34,
                    iconSize: 16,
                    cornerRadius: 9
                )
                VStack(alignment: .leading, spacing: 5) {
                    PlaceholderBar(width: 120)
                    PlaceholderBar(width: 76, light: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            Rectangle().fill(Palette.divider).frame(height: 1)

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    MockApp(highlighted: false) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Palette.neutral300)
                    }
                }
                MockApp(highlighted: true, label: L.s("onboarding_mock_more")) {
                    ZStack {
                        Circle().fill(Palette.neutral200)
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle().fill(Palette.neutral700).frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
        }
    }
}

/// 「その他」を開いた先のアプリ一覧。Pokkeがどう見えるかを示す
private struct MockAppList: View {
    var body: some View {
        MockSheet {
            HStack(spacing: 8) {
                LucideIconView(icon: Lucide.chevronLeft, size: 15, color: Palette.neutral700)
                PlaceholderBar(width: 54)
                Spacer(minLength: 0)
            }
            .padding(12)

            Rectangle().fill(Palette.divider).frame(height: 1)

            HStack(spacing: 0) {
                MockApp(highlighted: false) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.neutral300)
                }
                MockApp(highlighted: true, label: L.s("onboarding_mock_pokke")) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.accent)
                        LucideIconView(icon: Lucide.bookmark, size: 17, color: .white)
                    }
                }
                MockApp(highlighted: false) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.neutral300)
                }
                MockApp(highlighted: false) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.neutral300)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }
}

/// 図の共通の枠。白地＋細枠で「これは画面の絵である」と分かるようにする
private struct MockSheet<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: Corner.large, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Corner.large, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }
}

/// 図の中のアプリ1つぶん。名前を出すのは注目させたいものだけ
private struct MockApp<Icon: View>: View {
    let highlighted: Bool
    var label: String?
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 7) {
            icon()
                .frame(width: 42, height: 42)
                .overlay {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Palette.accent, lineWidth: 2)
                            .frame(width: 52, height: 52)
                    }
                }
            Group {
                if let label {
                    Text(label)
                        .font(PokkeType.labelSmall)
                        .foregroundStyle(Palette.neutral800)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    PlaceholderBar(width: 26, light: true)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }
}

/// 図の中の「文字の代わり」の灰色の帯
private struct PlaceholderBar: View {
    let width: CGFloat
    var light = false

    var body: some View {
        Capsule()
            .fill(light ? Palette.neutral200 : Palette.neutral300)
            .frame(width: width, height: 7)
    }
}

// MARK: - 3枚目: 実際に1回やってみる

private struct PracticePage: View {
    let waiting: Bool
    let onOpenShare: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingPage(
            primaryTitle: L.s("onboarding_open_share"),
            primaryIcon: Lucide.share,
            primaryEnabled: !waiting,
            onPrimary: onOpenShare,
            secondaryTitle: L.s("onboarding_try_later"),
            onSecondary: onSkip
        ) {
            Text(L.s("onboarding_practice_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(L.s("onboarding_practice_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            noticeCard
                .padding(.top, 22)

            Text(L.s("onboarding_practice_other_apps"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    /// 待っている間は同じカードを進行中の表示に差し替える。
    /// カードが増えたり減ったりすると、どこを見ればよいのか分からなくなる
    private var noticeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if waiting {
                ProgressView()
                    .tint(Palette.accent)
                    .frame(width: 38)
                    .padding(.top, 2)
            } else {
                IconTile(
                    icon: Lucide.link,
                    tint: Palette.accent2_100,
                    foreground: Palette.accent2_700,
                    size: 38,
                    iconSize: 17
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                if waiting {
                    Text(L.s("onboarding_waiting_title"))
                        .font(PokkeType.bodyLarge)
                        .foregroundStyle(Palette.ink)
                    Text(L.s("onboarding_waiting_lead"))
                        .font(PokkeType.bodyMedium)
                        .foregroundStyle(Palette.neutral800)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L.s("onboarding_practice_note"))
                        .font(PokkeType.bodyMedium)
                        .foregroundStyle(Palette.neutral800)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L.s("onboarding_practice_hint"))
                    .font(PokkeType.bodySmall)
                    .lineSpacing(5)
                    .foregroundStyle(Palette.accent800)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Corner.large, style: .continuous)
                .fill(waiting ? Palette.neutral100 : Palette.surface)
        )
        .softShadow(waiting ? .sm : .md)
    }
}

// MARK: - 4枚目: 保存された物を見せる

private struct DonePage: View {
    let item: StashItem?
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage(primaryTitle: L.s("onboarding_finish"), onPrimary: onFinish) {
            IconTile(
                icon: Lucide.check,
                tint: Palette.accent2_100,
                foreground: Palette.accent2_700,
                size: 64,
                iconSize: 30
            )
            .padding(.top, 24)

            Text(L.s("onboarding_done_title"))
                .font(PokkeType.headline)
                .foregroundStyle(Palette.ink)
                .padding(.top, 18)

            Text(L.s("onboarding_done_lead"))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let item {
                Text(L.s("onboarding_done_saved_label"))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .padding(.top, 24)

                // 見せるだけ。ここで詳細を開くと案内の途中で迷子になる
                ItemRow(item: item, showExcerpt: false) {}
                    .allowsHitTesting(false)
                    .padding(.top, 8)

                Text(L.s("onboarding_done_note"))
                    .font(PokkeType.bodySmall)
                    .lineSpacing(5)
                    .foregroundStyle(Palette.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            Text(L.s("onboarding_done_settings_note"))
                .font(PokkeType.bodySmall)
                .lineSpacing(5)
                .foregroundStyle(Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }
}

// MARK: - ページの外枠

/// 全ページ共通の骨。本文はスクロールし、ボタンだけは常に下に置いておく
private struct OnboardingPage<Content: View>: View {
    let primaryTitle: String
    var primaryIcon: Lucide.Icon?
    var primaryEnabled = true
    let onPrimary: () -> Void
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, screenPadding)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                PrimaryButton(
                    title: primaryTitle,
                    icon: primaryIcon,
                    height: 54,
                    enabled: primaryEnabled,
                    action: onPrimary
                )
                if let secondaryTitle, let onSecondary {
                    Button(action: onSecondary) {
                        Text(secondaryTitle)
                            .font(PokkeType.labelMedium)
                            .foregroundStyle(Palette.neutral700)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.accent : Palette.neutral300)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

// MARK: - ホームが空のときの案内

/// ホームが空のときに出す、共有からの保存を促す案内
struct ShareHintCard: View {
    let onShowGuide: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconTile(
                icon: Lucide.inbox,
                tint: Palette.accent100,
                foreground: Palette.accent700,
                size: 64,
                iconSize: 28
            )
            Text(L.s("home_empty"))
                .font(PokkeType.bodyLarge)
                .foregroundStyle(Palette.ink)
            Text(L.s("home_empty_hint"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            OutlinedPillButton(title: L.s("onboarding_show_guide"), action: onShowGuide)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 40)
    }
}
