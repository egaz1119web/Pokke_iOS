import SwiftUI

/// 共有拡張のコレクション選択カード。
///
/// 本体アプリ（Pokke/UI/Theme.swift）のPaletteはこのターゲットには含めていないので、
/// 見た目を合わせるための最小限の色だけをここに複製している。
///
/// 保存の入口は2つで、コレクションを選ぶか「とりあえず追加する」（＝ `onPick(nil)` で未分類）。
/// 幕の外を押したときだけは [onCancel] で、何も保存せずに閉じる。
struct SharePickerView: View {
    let url: String
    let collections: [StashCollection]
    let onPick: (String?) -> Void
    let onCancel: () -> Void

    private var host: String {
        guard let host = URLComponents(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                // 幕の向こうには共有元のアプリが透けて見えている。この状態で外側を押すのは
                // 「やっぱりやめる」なので、保存はしないで閉じる。
                // 入れ先を決めずに保存したいときは「とりあえず追加する」の方
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("share_pick_collection_title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SharePalette.ink)
                    Text(L.s("share_pick_collection_subtitle", host))
                        .font(.system(size: 13))
                        .foregroundStyle(SharePalette.ink.opacity(0.6))
                        .lineLimit(1)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(collections) { collection in
                            CollectionRow(collection: collection) { onPick(collection.id) }
                        }
                    }
                }
                .frame(maxHeight: 280)

                Button {
                    onPick(nil)
                } label: {
                    Text(L.s("share_add_now"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SharePalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Capsule().stroke(SharePalette.ink.opacity(0.25), lineWidth: 1.5)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(SharePalette.bg)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        // 本体アプリと同じくライト固定。システムのダークモードで背景だけ反転すると読みにくくなる
        .preferredColorScheme(.light)
    }
}

private struct CollectionRow: View {
    let collection: StashCollection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SharePalette.collectionColor(collection.colorIndex))
                        .frame(width: 36, height: 36)
                    Image(systemName: SharePalette.symbol(for: collection.icon))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SharePalette.ink)
                }
                Text(collection.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SharePalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Pokke/UI/Theme.swift の Palette / LucideIcons と揃えた値だけを、この拡張向けに複製したもの
private enum SharePalette {
    static let bg = Color(red: 0xF5 / 255, green: 0xEA / 255, blue: 0xD8 / 255)
    static let ink = Color(red: 0x33 / 255, green: 0x3A / 255, blue: 0x63 / 255)

    static let collectionColors: [Color] = [
        Color(red: 0xFF / 255, green: 0xF2 / 255, blue: 0xEB / 255),
        Color(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xD0 / 255),
        Color(red: 0xF0 / 255, green: 0xFA / 255, blue: 0xE1 / 255),
        Color(red: 0xE1 / 255, green: 0xEE / 255, blue: 0xCC / 255),
        Color(red: 0xEE / 255, green: 0xE7 / 255, blue: 0xDB / 255),
        Color(red: 0xDC / 255, green: 0xD3 / 255, blue: 0xC4 / 255),
    ]

    static func collectionColor(_ index: Int) -> Color {
        let count = collectionColors.count
        return collectionColors[((index % count) + count) % count]
    }

    private static let symbolByIcon: [String: String] = [
        "bookmark": "bookmark.fill",
        "utensils": "fork.knife",
        "gamepad": "gamecontroller.fill",
        "bulb": "lightbulb.fill",
        "headphones": "headphones",
        "plane": "airplane",
        "bag": "bag.fill",
        "clap": "hands.clap.fill",
        "briefcase": "briefcase.fill",
        "paw": "pawprint.fill",
        "star": "star.fill",
        "heart": "heart.fill",
    ]

    static func symbol(for icon: String) -> String {
        symbolByIcon[CollectionIcons.normalize(icon)] ?? "bookmark.fill"
    }
}
