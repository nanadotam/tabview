import AppKit
import QuickLookThumbnailing
import SwiftUI

/// State shared between the overlay window and the grid.
@Observable
final class TabGridModel {
    var tabs: [FinderTab] = []
    var app: SupportedApp = .finder
    var query = ""
    var highlighted = 0
    var presented = false
    /// Offscreen renders (README screenshots) can't use live blur, so they draw a solid backdrop.
    var solidBackdrop = false

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
                Text("\(model.tabs.count) \(model.app.name) Tab\(model.tabs.count == 1 ? "" : "s")")
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

                Button { model.onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.background.opacity(0.7), in: Circle())
                        .overlay(Circle().strokeBorder(.separator))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(Array(model.visibleTabs.enumerated()), id: \.element.id) { index, tab in
                            TabCard(tab: tab, showsFolder: model.app.showsFolders, highlighted: index == model.highlighted)
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
                                .scaleEffect(model.presented ? 1 : 0.94)
                                .opacity(model.presented ? 1 : 0)
                                .animation(.spring(duration: 0.24, bounce: 0.12).delay(min(Double(index), 12) * 0.008),
                                           value: model.presented)
                        }
                        if model.query.isEmpty, model.app.canOpenNewTab {
                            NewTabCard()
                                .onTapGesture { model.onNewTab() }
                                .opacity(model.presented ? 1 : 0)
                                .animation(.easeOut(duration: 0.2).delay(0.05), value: model.presented)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                // Clicking empty space dismisses, like Safari.
                .background(Color.black.opacity(0.0001).onTapGesture { model.onDismiss() })
                .onChange(of: model.highlighted) {
                    if model.visibleTabs.indices.contains(model.highlighted) {
                        withAnimation { scroller.scrollTo(model.visibleTabs[model.highlighted].id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if model.solidBackdrop {
                // Safari's overview grey, in both appearances.
                Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.88, alpha: 1)
                })
            } else {
                Rectangle().fill(.regularMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.55)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(model.presented ? 1 : 1.03)
        .opacity(model.presented ? 1 : 0)
        .animation(.spring(duration: 0.2, bounce: 0.05), value: model.presented)
        .onAppear { searchFocused = true }
    }
}

private struct TabCard: View {
    let tab: FinderTab
    let showsFolder: Bool
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

            // The preview lives in an overlay so a tall image can never stretch the card.
            Color(nsColor: .textBackgroundColor)
                .overlay {
                    if showsFolder {
                        FolderPreview(url: tab.url)
                    } else {
                        DocumentPreview(url: tab.url)
                    }
                }
                .clipped()
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
        .task(id: url) {
            guard let url else { return }
            // Paint whatever we had last time immediately, then refresh.
            if let cached = PreviewLoader.shared.cached(url) { items = cached }
            items = await PreviewLoader.shared.load(url)
        }
    }
}

/// A Quick Look render of the document itself, like Safari's page snapshots.
private struct DocumentPreview: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                // Fill the card width and pin to the top, like a page snapshot.
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                }
            } else {
                Image(systemName: "doc").font(.system(size: 30)).foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = PreviewLoader.shared.cachedDocument(url) { image = cached }
            image = await PreviewLoader.shared.loadDocument(url)
        }
    }
}

struct PreviewItem: Identifiable, @unchecked Sendable {
    let id: URL
    let name: String
    let image: NSImage
}

/// Loads Quick Look thumbnails for the first items in a folder.
/// Results are cached so the grid paints instantly next time; `load` always re-checks the folder.
final class PreviewLoader: @unchecked Sendable {
    static let shared = PreviewLoader()
    private var cache: [URL: [PreviewItem]] = [:]
    private let lock = NSLock()

    func cached(_ folder: URL) -> [PreviewItem]? {
        lock.withLock { cache[folder] }
    }

    func load(_ folder: URL) async -> [PreviewItem] {
        let files = await Task.detached(priority: .userInitiated) {
            ((try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .prefix(8)
        }.value

        // Reuse thumbnails we already have for files that are still there.
        let previous = Dictionary((cached(folder) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let result = await withTaskGroup(of: (Int, PreviewItem).self) { group in
            for (i, file) in files.enumerated() {
                group.addTask {
                    if let hit = previous[file] { return (i, hit) }
                    return (i, PreviewItem(id: file, name: file.lastPathComponent, image: await Self.thumbnail(for: file)))
                }
            }
            var out: [(Int, PreviewItem)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        lock.withLock { cache[folder] = result }
        return result
    }

    private var documents: [URL: NSImage] = [:]

    func cachedDocument(_ file: URL) -> NSImage? {
        lock.withLock { documents[file] }
    }

    func loadDocument(_ file: URL) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 360, height: 360), scale: 2, representationTypes: .thumbnail)
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
            ?? NSWorkspace.shared.icon(forFile: file.path)
        lock.withLock { documents[file] = image }
        return image
    }

    /// Warm the cache in the background so the next open has previews ready.
    func prefetch(_ urls: [URL], documents: Bool = false) {
        for url in urls {
            if documents {
                guard cachedDocument(url) == nil else { continue }
                Task.detached(priority: .utility) { _ = await self.loadDocument(url) }
            } else {
                guard cached(url) == nil else { continue }
                Task.detached(priority: .utility) { _ = await self.load(url) }
            }
        }
    }

    private static func thumbnail(for file: URL) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: [.icon, .thumbnail])
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.nsImage
        }
        return NSWorkspace.shared.icon(forFile: file.path)
    }
}
