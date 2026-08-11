import SwiftUI

/// デザインシステムの共通部品。Android版 `ui/Components.kt` に対応する。
///
/// SwiftUI既定のコンポーネントをそのまま使うとシステムの色・角丸が混ざるので、
/// 見た目を決める要素（面・影・枠・押下時の縮み）はここに集約している。

// MARK: - アニメーション

/// アニメーションを挟まずに状態を変える。
///
/// ページ送り（`TabView(.page)`）を含む画面では、既定のままだと
/// ページ差し替えのアニメーションが同じ更新に相乗りしてしまい、
/// 直接は関係ないセグメントの白い面まで、0.5秒かけてゆっくり浮かび上がってくる。
/// 押した瞬間に切り替わってほしいところは、これで包む。
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

// MARK: - 押下

/// 押したときに少し縮むボタン。
///
/// カードは .98、ボタンは .95 くらいが目安。iOSの既定のハイライトだけだと
/// 白いカードの上では反応が見えにくいので、形の変化で補っている。
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static func pressScale(_ scale: CGFloat = 0.98) -> PressScaleButtonStyle {
        PressScaleButtonStyle(scale: scale)
    }
}

// MARK: - 面

/// 白いカード。角丸22pt・shadow-sm
///
/// [borderColor] は枠で状態を示したいとき（編集モードで選ばれている等）に使う。
struct PokkeCard<Content: View>: View {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = Corner.large
    var borderColor: Color = .clear
    var action: (() -> Void)?
    var onLongPress: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var pressing = false

    var body: some View {
        if let action {
            if let onLongPress {
                // 長押しを拾う必要があるときは Button を使わない。
                // Button に長押しのジェスチャーを重ねると、指を離したときに
                // タップまで続けて成立してしまう（＝選び直しが起きる）。
                // タップと長押しを同じ層に置けば、SwiftUI がどちらか一方に決める
                surface
                    .scaleEffect(pressing ? 0.98 : 1)
                    .animation(.easeOut(duration: 0.12), value: pressing)
                    .onTapGesture(perform: action)
                    .onLongPressGesture(minimumDuration: 0.45) {
                        onLongPress()
                    } onPressingChanged: { pressing = $0 }
                    .accessibilityAddTraits(.isButton)
            } else {
                Button(action: action) { surface }
                    .buttonStyle(.pressScale())
            }
        } else {
            surface
        }
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 2)
            )
            .softShadow(.sm)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 選択中かどうかを示す丸いチェック。編集モードのカードに添える。
///
/// 選んでいない間も枠だけ出しておく。出したり消したりすると、
/// どこを押せば選べるのかが分からない
struct SelectionCheck: View {
    let selected: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(selected ? Palette.accent : Palette.surface.opacity(0.92))
            if selected {
                LucideIconView(icon: Lucide.check, size: size * 0.55, color: .white)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(selected ? Palette.accent : Palette.neutral400, lineWidth: 1.5)
        )
    }
}

/// 角丸の面に線画アイコンを1つ置く。サムネイル代わりやコレクションの丸章に使う
struct IconTile: View {
    let icon: Lucide.Icon
    var tint: Color
    var foreground: Color
    var size: CGFloat
    var iconSize: CGFloat
    /// nil なら円。値があれば角丸の四角
    var cornerRadius: CGFloat?

    init(
        icon: Lucide.Icon,
        tint: Color,
        foreground: Color,
        size: CGFloat,
        iconSize: CGFloat,
        cornerRadius: CGFloat? = nil
    ) {
        self.icon = icon
        self.tint = tint
        self.foreground = foreground
        self.size = size
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if let cornerRadius {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint)
            } else {
                Circle().fill(tint)
            }
            LucideIconView(icon: icon, size: iconSize, color: foreground)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - ボタン

/// ヘッダーの「＋」や「戻る」に使う、白い丸ボタン
struct CircleIconButton: View {
    let icon: Lucide.Icon
    let accessibilityLabel: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 19
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Palette.surface).softShadow(.sm)
                LucideIconView(icon: icon, size: iconSize, color: Palette.ink)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.pressScale(0.92))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 主ボタン。全幅のテラコッタのピル
struct PrimaryButton: View {
    let title: String
    var icon: Lucide.Icon?
    var height: CGFloat = 52
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(enabled ? Color.white : Palette.neutral600)
                if let icon {
                    LucideIconView(icon: icon, size: 17, color: enabled ? .white : Palette.neutral600)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(enabled ? Palette.accent : Palette.neutral300))
            .softShadow(enabled ? .md : .sm)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.985))
        .disabled(!enabled)
    }
}

/// 白地に細枠のピルボタン
struct OutlinedPillButton: View {
    let title: String
    var height: CGFloat = 42
    var fullWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 22)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.97))
    }
}

/// 詳細シートの4等分アクション（アイコン＋小さなラベルの縦積み）。
/// 削除だけは [contentColor] を濃いテラコッタにして、他と区別する。
struct StackedActionButton: View {
    let icon: Lucide.Icon
    let label: String
    var contentColor: Color = Palette.ink
    var borderColor: Color = Palette.hairline
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                LucideIconView(icon: icon, size: 17, color: contentColor.opacity(enabled ? 1 : 0.4))
                Text(label)
                    .font(PokkeType.labelSmall)
                    .foregroundStyle(contentColor.opacity(enabled ? 1 : 0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Corner.medium, style: .continuous).fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Corner.medium, style: .continuous))
        }
        .buttonStyle(.pressScale(0.95))
        .disabled(!enabled)
    }
}

// MARK: - セグメント

/// ピルの中に入れ子のピルを並べるセグメント。
/// 未読／アーカイブ、リスト／グリッドで共通に使う。
struct SegmentedPills<Content: View>: View {
    var containerColor: Color = Palette.surface.opacity(0.55)
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 3, content: content)
            .padding(3)
            .background(Capsule().fill(containerColor))
    }
}

/// [SegmentedPills] の中身。選択中だけ白い面と影が付く
struct SegmentPill<Content: View>: View {
    let selected: Bool
    var horizontalPadding: CGFloat = 13
    var width: CGFloat?
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6, content: content)
                .padding(.horizontal, horizontalPadding)
                .frame(width: width)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(selected ? Palette.surface : Color.clear)
                        .softShadow(selected ? .sm : .sm)
                        .opacity(selected ? 1 : 0)
                )
                .contentShape(Capsule())
                // 選択の見た目は押した瞬間に入れ替える。
                // 文字色は SwiftUI が補間しないので黙っていても即時だが、線画アイコンは
                // 図形の線色＝補間される値なので、外から流れてきたアニメーションに
                // 乗って0.4秒かけてじわっと色が変わってしまう。
                // ボタンの外側に付けても中身までは届かないので、ラベルの中に置く
                .transaction { $0.animation = nil }
        }
        .buttonStyle(.plain)
    }
}

/// リスト／グリッドの切り替え。ホームとコレクション詳細で同じものを使う。
///
/// 選んだ形は `AppPrefs.viewMode` にそのまま入るので、どちらの画面で切り替えても
/// もう一方に効く。画面ごとに別々に覚えると、同じリンクの見え方が場所によって
/// 変わってしまい、切り替えたつもりが効いていないように見える。
struct ViewModeToggle: View {
    @ObservedObject private var prefs = AppPrefs.shared

    var body: some View {
        SegmentedPills {
            ViewModePill(
                icon: Lucide.listView,
                label: L.s("view_list"),
                selected: prefs.viewMode == .list
            ) { prefs.setViewMode(.list) }
            ViewModePill(
                icon: Lucide.grid,
                label: L.s("view_grid"),
                selected: prefs.viewMode == .grid
            ) { prefs.setViewMode(.grid) }
        }
    }
}

private struct ViewModePill: View {
    let icon: Lucide.Icon
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SegmentPill(selected: selected, horizontalPadding: 9, width: 36, action: action) {
            LucideIconView(icon: icon, size: 17, color: selected ? Palette.ink : Palette.neutral700)
                .accessibilityLabel(label)
        }
    }
}

/// 横に並ぶサービス／タグのチップ。活性はインク地に白文字
struct ServiceChip<Icon: View>: View {
    let label: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(label)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(selected ? Color.white : Palette.neutral700)
                    .lineLimit(1)
                Text("\(count)")
                    .font(PokkeType.bodySmall)
                    .foregroundStyle((selected ? Color.white : Palette.neutral700).opacity(0.6))
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule().fill(selected ? Palette.ink : Palette.surface))
            .overlay(
                Capsule().stroke(
                    selected ? Color.clear : Palette.neutral500.opacity(0.3),
                    lineWidth: 1.5
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
    }
}

extension ServiceChip where Icon == EmptyView {
    init(label: String, count: Int, selected: Bool, action: @escaping () -> Void) {
        self.init(label: label, count: count, selected: selected, action: action) { EmptyView() }
    }
}

// MARK: - スイッチ

/// 46×26のトグル。ONでテラコッタ
struct PokkeSwitch: View {
    @Binding var isOn: Bool
    let accessibilityLabel: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Palette.accent : Palette.neutral300)
                .frame(width: 46, height: 26)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Palette.surface)
                        .softShadow(.sm)
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 22 : 2)
                }
                .animation(.easeInOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - 文字

/// 画面タイトル（24pt・丸ゴシック）
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PokkeType.headline)
            .foregroundStyle(Palette.ink)
    }
}

/// カードの上に置く小さなセクション見出し
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PokkeType.labelMedium)
            .foregroundStyle(Palette.neutral600)
            .padding(.horizontal, 2)
    }
}

/// アイコン＋一行メッセージの空状態
struct EmptyState: View {
    let icon: Lucide.Icon
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            LucideIconView(icon: icon, size: 34, color: Palette.neutral400)
            Text(message)
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral600)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

// MARK: - トースト

/// 画面下に一瞬だけ出る小さな通知。
///
/// 標準のアラートやバナーはこの配色から浮くのでアプリ内で描いている。
@MainActor
final class ToastController: ObservableObject {
    @Published private(set) var message: String?

    private var task: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        // 連続で出したときに前の消去タイマーで消えないよう、毎回引き直す
        task?.cancel()
        task = Task { [weak self] in
            // AndroidのToast.LENGTH_SHORT（約2秒）と同じくらい。
            // これより短いと和文を読み切る前に消えてしまう
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

/// トースト本体。ボトムナビに被らないよう既定で下から96pt上げる
struct ToastHost: View {
    @ObservedObject var controller: ToastController
    /// シートの上に重ねるときはボトムナビが無いので詰める
    var bottomPadding: CGFloat = 96

    var body: some View {
        ZStack {
            if let message = controller.message {
                Text(message)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Palette.ink))
                    .softShadow(.lg)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: controller.message)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, bottomPadding)
        .allowsHitTesting(false)
    }
}

extension View {
    /// シートの中から出したトーストを、そのシート自身の上に重ねる。
    ///
    /// `RootView` に置いた [ToastHost] はシートより下の層にいるので、
    /// シートを閉じない操作（画像の保存など）ではトーストが背後に隠れて
    /// 「押しても何も起きない」ように見えてしまう。
    func toastOverlay(_ controller: ToastController, bottomPadding: CGFloat = 34) -> some View {
        overlay(ToastHost(controller: controller, bottomPadding: bottomPadding))
    }
}

// MARK: - 入力・区切り

/// 入力欄などに使う、白地・細枠のピル
struct PillField<Content: View>: View {
    var focused: Bool = false
    var height: CGFloat = 50
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Palette.surface))
            .overlay(
                Capsule().stroke(
                    focused ? Palette.accent : Palette.ink.opacity(0.12),
                    lineWidth: 1.5
                )
            )
    }
}

/// ボトムシートのつまみ。
/// 標準のグラバーは太く濃くて、クリーム地のシートでは強すぎるので置き換える
struct SheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Palette.neutral300)
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }
}

/// カード内の区切り線
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Palette.divider).frame(height: 1)
    }
}
