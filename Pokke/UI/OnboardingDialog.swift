import SwiftUI

/// 初回起動時に「他のアプリの共有から保存できる」ことを伝える案内
struct OnboardingDialog: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x201E1D).opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    IconTile(
                        icon: Lucide.share,
                        tint: Palette.accent100,
                        foreground: Palette.accent700,
                        size: 48,
                        iconSize: 22
                    )
                    Text(L.s("onboarding_title"))
                        .font(PokkeType.titleMedium)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 12)
                    Text(L.s("onboarding_lead"))
                        .font(PokkeType.bodyMedium)
                        .lineSpacing(PokkeType.bodyLineSpacing)
                        .foregroundStyle(Palette.neutral800)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        Step(number: 1, textKey: "onboarding_step1")
                        Step(number: 2, textKey: "onboarding_step2")
                        Step(number: 3, textKey: "onboarding_step3")
                    }
                    .padding(.top, 16)

                    Text(L.s("onboarding_footnote"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    PrimaryButton(title: L.s("onboarding_got_it"), height: 48, action: onDismiss)
                        .padding(.top, 20)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: Corner.extraLarge, style: .continuous)
                        .fill(Palette.bg)
                )
                .softShadow(.lg)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
    }
}

private struct Step: View {
    let number: Int
    let textKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Palette.accent)
                Text("\(number)")
                    .font(PokkeType.labelSmall)
                    .foregroundStyle(Color.white)
            }
            .frame(width: 24, height: 24)

            Text(L.s(textKey))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
    }
}

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
