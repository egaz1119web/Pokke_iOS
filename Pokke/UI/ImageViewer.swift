import SwiftUI

/// 拡大時に指で動かせる倍率の上限
private let maxZoom: CGFloat = 5

/// 画像を全画面で見るビューア。
///
/// 一覧・詳細のサムネイルは枠に合わせて切り抜いているので、
/// ここでは切らずに画像全体を表示する。
/// ピンチで拡大、ドラッグで移動、タップで閉じる。
struct ImageViewerView: View {
    let imageUrl: String
    let onDismiss: () -> Void
    var onSave: (() -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.93).ignoresSafeArea()

            AsyncImage(url: URL(string: imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    LucideIconView(icon: Lucide.image, size: 48, color: .white.opacity(0.5))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = min(max(pinchBase * value, 1), maxZoom)
                        }
                        .onEnded { _ in
                            pinchBase = zoom
                            // 等倍に戻したら位置もリセットして画面外に取り残されないようにする
                            if zoom <= 1 { offset = .zero; dragBase = .zero }
                        },
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1 else { return }
                            offset = CGSize(
                                width: dragBase.width + value.translation.width,
                                height: dragBase.height + value.translation.height
                            )
                        }
                        .onEnded { _ in dragBase = offset }
                )
            )
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture {
                if zoom > 1 { resetZoom() } else { onDismiss() }
            }

            // 画像が暗くて閉じ方が分かりにくいことがあるので明示的に出す
            VStack {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if let onSave {
                        CircleOverlayButton(
                            icon: Lucide.download,
                            accessibilityLabel: L.s("detail_save_image"),
                            action: onSave
                        )
                    }
                    CircleOverlayButton(
                        icon: Lucide.x,
                        accessibilityLabel: L.s("action_close"),
                        action: onDismiss
                    )
                }
                .padding(12)
                Spacer(minLength: 0)
            }
        }
        .animation(.easeOut(duration: 0.2), value: zoom)
    }

    private func toggleZoom() {
        if zoom > 1 { resetZoom() } else { zoom = 2.5; pinchBase = 2.5 }
    }

    private func resetZoom() {
        zoom = 1
        pinchBase = 1
        offset = .zero
        dragBase = .zero
    }
}

/// 全画面ビューア上の丸ボタン
private struct CircleOverlayButton: View {
    let icon: Lucide.Icon
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.45))
                LucideIconView(icon: icon, size: 19, color: .white)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 画像をタップして拡大できることを示す小さなヒント
struct TapToExpandHint: View {
    var body: some View {
        Text(L.s("detail_tap_to_expand"))
            .font(PokkeType.labelSmall)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.ink.opacity(0.78)))
    }
}
