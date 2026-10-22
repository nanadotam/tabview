import AppKit
import QuickLookThumbnailing
import SwiftUI

/// State shared between the overlay window and the grid.
@Observable
final class TabGridModel {
    var tabs: [FinderTab] = []
    var query = ""
    var highlighted = 0
    var presented = false

    var onOpen: (FinderTab) -> Void = { _ in }
    var onClose: (FinderTab) -> Void = { _ in }
    var onNewTab: () -> Void = {}
    var onDismiss: () -> Void = {}

    var visibleTabs: [FinderTab] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tabs }
        return tabs.filter {
            $0.title.localizedCaseInsensitiveContains(q) || ($0.url?.path.localizedCaseInsensitiveContains(q) ?? false)
        }
    }
}

struct TabGridView: View {
    @Bindable var model: TabGridModel
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 22)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.tabs.count) Finder Tab\(model.tabs.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Tabs", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onChange(of: model.query) { model.highlighted = 0 }
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 28)
                .background(.background.opacity(0.7), in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(Array(model.visibleTabs.enumerated()), id: \.element.id) { index, tab in
                            TabCard(tab: tab, highlighted: index == model.highlighted)
                                .id(tab.id)
                                .onTapGesture { model.onOpen(tab) }
                                .onHover { if $0 { model.highlighted = index } }
                                .overlay(alignment: .topLeading) {
                                    Button { model.onClose(tab) } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(width: 22, height: 22)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 6)
                                    .padding(.top, 5)
                                }
                                .scaleEffect(model.presented ? 1 : 0.92)
                                .opacity(model.presented ? 1 : 0)
                                .animation(.spring(duration: 0.38, bounce: 0.18).delay(Double(index) * 0.02),
                                           value: model.presented)
                        }
                        if model.query.isEmpty {
                            NewTabCard()
                                .onTapGesture { model.onNewTab() }
                                .opacity(model.presented ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.1), value: model.presented)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .onChange(of: model.highlighted) {
                    if model.visibleTabs.indices.contains(model.highlighted) {
                        withAnimation { scroller.scrollTo(model.visibleTabs[model.highlighted].id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(model.presented ? 1 : 1.04)
        .opacity(model.presented ? 1 : 0)
        .animation(.spring(duration: 0.3, bounce: 0.1), value: model.presented)
        .onAppear { searchFocused = true }
    }
}

private struct TabCard: View {
    let tab: FinderTab
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 24)
                if let url = tab.url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 16, height: 16)
                }
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 24)
            }
            .frame(height: 30)
            .background(.background)

            FolderPreview(url: tab.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .aspectRatio(1.5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: highlighted ? 3 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if tab.isActive {
                Text("Current")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(highlighted ? 0.18 : 0.08), radius: highlighted ? 10 : 4, y: 2)
        .scaleEffect(highlighted ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .contentShape(Rectangle())
    }
}

private struct NewTabCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .aspectRatio(1.5, contentMode: .fit)
            .overlay(Image(systemName: "plus").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary))
            .contentShape(Rectangle())
    }
}

/// A miniature icon view of the first few items in a folder.
private struct FolderPreview: View {
    let url: URL?
    @State private var items: [PreviewItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        Group {
            if url == nil {
                Image(systemName: "folder").font(.system(size: 30)).foregroundStyle(.tertiary)
            } else if items.isEmpty {
                Color.clear
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(items) { item in
                        VStack(spacing: 2) {
                            Image(nsImage: item.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 34)
                            Text(item.name)
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: url) { if let url { items = await PreviewLoader.shared.items(in: url) } }
    }
}

struct PreviewItem: Identifiable {
    let id: URL
    let name: String
    let image: NSImage
}

/// Loads (and caches) Quick Look thumbnails for the first items in a folder.
actor PreviewLoader {
    static let shared = PreviewLoader()
    private var cache: [URL: [PreviewItem]] = [:]

    func items(in folder: URL) async -> [PreviewItem] {
        if let hit = cache[folder] { return hit }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let first = contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(8)

        var result: [PreviewItem] = []
        for file in first {
            result.append(PreviewItem(id: file, name: file.lastPathComponent, image: await thumbnail(for: file)))
        }
        cache[folder] = result
        return result
    }

    func invalidate() { cache.removeAll() }

    private func thumbnail(for file: URL) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: [.icon, .thumbnail])
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: file.path)
    }
}
