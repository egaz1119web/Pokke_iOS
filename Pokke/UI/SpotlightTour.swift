import SwiftUI

/// スポットライトを当てる先。実際の枠は各画面が [spotlightAnchor] で登録する
enum SpotlightTarget: Hashable {
    case savedItem
    case filters
    case addLink
    case nav
}

/// 「どの部品が画面のどこにいるか」を、上に重ねる案内へ運ぶ。
///
/// 座標を案内側に書き写す方式だと、ヘッダーの高さを1pt変えただけで
/// 穴が対象からずれる。対象そのものの枠を送る形にしておく。
struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [SpotlightTarget: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [SpotlightTarget: Anchor<CGRect>],
        nextValue: () -> [SpotlightTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    /// この要素をスポットライトの対象として登録する。
    /// 同じ対象が2か所から登録されると穴が定まらないので、出し分けは [active] で行う
    func spotlightAnchor(_ target: SpotlightTarget, active: Bool = true) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { anchor in
            active ? [target: anchor] : [:]
        }
    }
}

/// 案内1コマ
struct SpotlightStep {
    let target: SpotlightTarget
    let icon: Lucide.Icon
    let titleKey: String
    let bodyKey: String
    /// 穴の角丸。対象の角丸に合わせる
    var cornerRadius: CGFloat = Corner.large
    /// 対象の周りに足す余白。丸ボタンのように輪郭ぎりぎりの物は小さめでよい
    var inset: CGFloat = 8
}

extension SpotlightStep {
    /// 初回案内で1件目を保存できた直後、ホームで流す5コマ
    static let afterFirstSave: [SpotlightStep] = [
        SpotlightStep(
            target: .savedItem,
            icon: Lucide.circleCheck,
            titleKey: "tour_saved_title",
            bodyKey: "tour_saved_body"
        ),
        SpotlightStep(
            target: .filters,
            icon: Lucide.archive,
            titleKey: "tour_filter_title",
            bodyKey: "tour_filter_body",
            cornerRadius: 22,
            inset: 4
        ),
        SpotlightStep(
            target: .addLink,
            icon: Lucide.plus,
            titleKey: "tour_add_title",
            bodyKey: "tour_add_body",
            cornerRadius: 26,
            inset: 5
        ),
        SpotlightStep(
            target: .nav,
            icon: Lucide.folder,
            titleKey: "tour_nav_title",
            bodyKey: "tour_nav_body",
            cornerRadius: 22,
            inset: 2
        ),
        // 最後にもう一度カードを指して、長押しでまとめて片付けられることを伝える。
        // 保存したその場では要らない話なので、他をひととおり見せた後に置いている
        SpotlightStep(
            target: .savedItem,
            icon: Lucide.check,
            titleKey: "tour_edit_title",
            bodyKey: "tour_edit_body"
        ),
    ]
}

/// 画面を暗く落として1か所だけ切り抜く案内。
///
/// 初回案内の中で文章にして並べる形も試したが、実物を見る前の説明は
/// 読み飛ばされる。実際に保存できた直後の本物のホームの上で、
/// 対象そのものを指して1つずつ出す。
struct SpotlightOverlay: View {
    let steps: [SpotlightStep]
    let index: Int
    /// 今のコマの対象の枠。畳まれていて見えないときは nil。そのときは穴を開けずに文だけ出す
    let hole: CGRect?
    let size: CGSize
    let onNext: () -> Void
    let onClose: () -> Void

    /// 穴と吹き出しの間隔
    private let gap: CGFloat = 14

    private var step: SpotlightStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        ZStack {
            dimming
            if let hole {
                spotRing(hole)
            }
            balloon
        }
        .frame(width: size.width, height: size.height)
        // 後ろを触られると穴の位置と画面の中身がずれる。案内の間は素通しにしない。
        // どこを押しても次へ進むので、押しどころを探して止まることもない
        .contentShape(Rectangle())
        .onTapGesture(perform: onNext)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - 穴

    private var dimming: some View {
        ZStack {
            Palette.ink.opacity(0.62)
            if let hole {
                holeShape
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
                    // 覆いから対象のぶんだけ削る。ここは合成の対象を
                    // 覆いだけに閉じたいので、外側で compositingGroup する
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    private func spotRing(_ hole: CGRect) -> some View {
        holeShape
            .stroke(Palette.accent, lineWidth: 2.5)
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
            .shadow(color: Palette.accent.opacity(0.45), radius: 10)
            .allowsHitTesting(false)
    }

    private var holeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
    }

    // MARK: - 吹き出し

    /// 穴を避けて、空いている側に置く
    @ViewBuilder
    private var balloon: some View {
        if let hole {
            if size.height - hole.maxY >= hole.minY {
                VStack(spacing: 0) {
                    Spacer(minLength: 0).frame(height: min(hole.maxY + gap, size.height))
                    card
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    card
                    Spacer(minLength: 0)
                        .frame(height: min(max(size.height - hole.minY + gap, 0), size.height))
                }
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                IconTile(
                    icon: step.icon,
                    tint: Palette.accent100,
                    foreground: Palette.accent700,
                    size: 38,
                    iconSize: 19
                )
                Text(L.s(step.titleKey))
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L.s(step.bodyKey))
                .font(PokkeType.bodyMedium)
                .lineSpacing(PokkeType.bodyLineSpacing)
                .foregroundStyle(Palette.neutral800)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 14) {
                PageDots(count: steps.count, current: index)
                Spacer(minLength: 0)
                // 最後の1コマは「わかりました」しか行き先が無いので、抜ける導線は出さない
                if !isLast {
                    Button(action: onClose) {
                        Text(L.s("onboarding_skip"))
                            .font(PokkeType.labelMedium)
                            .foregroundStyle(Palette.neutral700)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onNext) {
                    Text(L.s(isLast ? "onboarding_got_it" : "tour_next"))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .background(Capsule().fill(Palette.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressScale(0.95))
            }
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Corner.large, style: .continuous).fill(Palette.surface)
        )
        .softShadow(.lg)
        .padding(.horizontal, screenPadding)
    }
}
