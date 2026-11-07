import SwiftUI

/// Lays its children out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, maxWidth: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var rowStart = 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0

        func finishRow() {
            // Centre each child vertically in its row.
            for i in rowStart..<frames.count {
                frames[i].origin.y = y + (rowHeight - frames[i].height) / 2
            }
            rowStart = frames.count
            y += rowHeight + spacing
            x = 0
            rowHeight = 0
        }

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + size.width > maxWidth { finishRow() }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        finishRow()
        return (frames, CGSize(width: usedWidth, height: max(0, y - spacing)))
    }
}

/// A `#tag` capsule: tapping runs `action`; `onRemove` adds a remove button.
struct TagChip: View {
    let tag: String
    var count: Int? = nil
    var isSelected = false
    var action: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text("#\(tag)").truncationMode(.middle)
                    if let count { Text("\(count)").opacity(0.7) }
                }
                .padding(.leading, 8)
                .padding(.trailing, onRemove == nil ? 8 : 4)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.trailing, 7)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove #\(tag)")
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(isSelected ? Theme.onAccent : Theme.accent)
        .background(Capsule().fill(isSelected ? Theme.accent : Theme.accent.opacity(0.1)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Search pinned above the sidebar. Plain words search page titles, summaries, folders and
/// tags; `@word` searches tags and shows the matching tag chips (`@` alone lists them all), so
/// the library's full tag list never crowds the top of the sidebar.
struct TagFilterBar: View {
    @EnvironmentObject var store: VaultStore
    @State private var chipsHeight: CGFloat = 24

    var body: some View {
        if !store.links.pages.isEmpty || store.isFilteringByTag {
            VStack(alignment: .leading, spacing: 8) {
                searchField
                let tags = store.isFilteringByTag ? store.visibleTags : []
                if !tags.isEmpty {
                    // As tall as the chips, scrolling once there are too many.
                    ScrollView {
                        chips(tags).onGeometryChange(for: CGFloat.self, of: \.size.height) { chipsHeight = $0 }
                    }
                    .frame(height: min(chipsHeight, 84))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search, or @tag", text: $store.tagQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search pages; start a word with @ to search tags")
                .help("Search page titles, summaries, keywords and folders. Start a word with @ to search tags; @ alone lists them all.")
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if store.isFilteringByTag {
                Button { store.clearTagFilter() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hairline))
    }

    private func chips(_ tags: [LinkIndex.TagCount]) -> some View {
        FlowLayout {
            ForEach(tags) { item in
                TagChip(tag: item.tag,
                        count: item.count,
                        isSelected: store.selectedTags.contains(item.tag),
                        action: { store.toggleTag(item.tag) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tag search result: a topic, a subtopic or a page, with where it lives.
struct TagResultRow: View {
    @EnvironmentObject var store: VaultStore
    let page: LinkIndex.Page

    var body: some View {
        let node = store.nodeURL(forPage: page.url)
        let location = store.relativePath(node.deletingLastPathComponent())
        let file = FileNode(url: page.url, name: page.url.lastPathComponent, isDirectory: false, children: nil)
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.sidebarLabel(for: file)).lineLimit(1)
                Text(location.isEmpty ? "Topic" : location)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: icon(node: node, location: location))
                .frame(width: 20)   // symbols differ in width; keep the titles aligned
        }
        .help(page.tags.map { "#\($0)" }.joined(separator: " "))
    }

    private func icon(node: URL, location: String) -> String {
        guard node != page.url else { return "doc.richtext" }
        return location.isEmpty ? "books.vertical" : "folder"
    }
}

/// The tags of the page on screen, with a field to add more. Typing suggests tags already
/// used in the library, which keeps spellings consistent; tapping a tag searches for it.
struct PageTagBar: View {
    @EnvironmentObject var store: VaultStore
    let page: URL

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let tags = store.links.pages[page.standardizedFileURL]?.tags ?? []
        let suggestions = suggestions(excluding: tags)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag,
                                action: { store.showTag(tag) },
                                onRemove: { store.removeTag(tag, from: page) })
                    }
                    TextField(tags.isEmpty ? "Add a tag" : "Add", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 120)
                        .focused($fieldFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(commit)
                        .accessibilityLabel("Add a tag")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !suggestions.isEmpty {
                FlowLayout {
                    ForEach(suggestions, id: \.self) { tag in
                        TagChip(tag: tag, action: { add(tag) })
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func suggestions(excluding tags: [String]) -> [String] {
        let typed = PageTags.normalize(draft)
        guard !typed.isEmpty else { return [] }
        let matches = store.links.tagList.map(\.tag).filter { $0.contains(typed) && !tags.contains($0) }
        return Array(matches.prefix(6))
    }

    private func commit() { add(draft) }

    private func add(_ list: String) {
        store.addTags(list, to: page)
        draft = ""
        fieldFocused = true
    }
}
