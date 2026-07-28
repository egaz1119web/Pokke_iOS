import SwiftUI

/// アイテム詳細のボトムシート
struct DetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: StashItem
    let collections: [StashCollection]

    @State private var tagInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HStack(spacing: 8) {
                    Button {
                        openLink(item)
                        dismiss()
                    } label: {
                        Text(L.s("action_open"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.primary)

                    Button {
                        StashRepository.shared.setArchived(id: item.id, archived: !item.archived)
                        dismiss()
                    } label: {
                        Text(L.s(item.archived ? "detail_unarchive" : "detail_archive"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.primary)
                }
                .padding(.top, 16)

                Text(L.s("detail_collections"))
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                collectionChips

                Text(L.s("detail_tags"))
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                tagSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.appBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Thumbnail(item: item, size: 72, corner: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Palette.onSurface)
                    .multilineTextAlignment(.leading)
                Text(L.s("detail_meta", item.siteName ?? item.host, relativeTime(item.savedAt)))
                    .font(.caption)
                    .foregroundStyle(Palette.onSurfaceVariant)
                if item.openCount > 0 {
                    Text(L.plural("detail_reopen_count", item.openCount))
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var collectionChips: some View {
        if collections.isEmpty {
            Text(L.s("detail_no_collections"))
                .font(.caption)
                .foregroundStyle(Palette.onSurfaceVariant)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(collections) { collection in
                    let selected = item.collectionId == collection.id
                    // 選択中の色差だけだと分かりにくいのでチェックを足す
                    FilterChipView(
                        label: (selected ? "✓ " : "") + "\(collection.emoji) \(collection.name)",
                        selected: selected
                    ) {
                        var updated = item
                        updated.collectionId = selected ? nil : collection.id
                        StashRepository.shared.updateItem(updated)
                    }
                }
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        FilterChipView(label: "#\(tag) ✕", selected: false) {
                            var updated = item
                            updated.tags.removeAll { $0 == tag }
                            StashRepository.shared.updateItem(updated)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(L.s("detail_add_tag"), text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTag)
                Button(L.s("action_add"), action: addTag)
                    .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addTag() {
        var tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.hasPrefix("#") { tag = String(tag.dropFirst()) }
        if !tag.isEmpty && !item.tags.contains(tag) {
            var updated = item
            updated.tags.append(tag)
            StashRepository.shared.updateItem(updated)
        }
        tagInput = ""
    }
}

/// ComposeのFlowRow相当。入りきらなくなったら折り返す横並び
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
