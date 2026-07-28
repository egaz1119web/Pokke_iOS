import SwiftUI

/// Googleの4色ロゴ。
///
/// ブランドガイドラインで色と形が決まっているので、テーマ色を当てず塗りをそのまま持つ。
/// 単色に潰さないこと（Lucideのアイコンとは扱いが違う）。
struct GoogleLogo: View {
    var size: CGFloat = 18

    private static let paths: [(Color, String)] = [
        (Color(hex: 0xEA4335), "M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"),
        (Color(hex: 0x4285F4), "M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"),
        (Color(hex: 0xFBBC05), "M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"),
        (Color(hex: 0x34A853), "M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.paths.enumerated()), id: \.offset) { _, entry in
                FilledPath(data: entry.1).fill(entry.0)
            }
        }
        .frame(width: size, height: size)
    }

    private struct FilledPath: Shape {
        let data: String

        func path(in rect: CGRect) -> Path {
            // ロゴのビューポートは48
            let scale = min(rect.width, rect.height) / 48
            return SVGPath.parse(data).applying(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
}
