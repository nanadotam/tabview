import AppKit
import SwiftUI

/// `Tabview --render-readme <out-dir> [demo-folders-dir]`
/// Renders the README screenshots offscreen from demo folders, so they never show anyone's real files.
enum ReadmeRenderer {
    static func run(output: URL, demo: URL?) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folders = demo.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        }?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        // Folder names may carry an order prefix ("1 Brand Assets"); the tab title drops it.
        let tabs = folders.enumerated().map { i, url in
            FinderTab(id: i, title: url.lastPathComponent.split(separator: " ", maxSplits: 1).last.map(String.init) ?? "",
                      url: url, isActive: i == 2, button: nil)
        }
        for url in folders { _ = waitFor { await PreviewLoader.shared.load(url) } }

        let model = TabGridModel()
        model.tabs = tabs
        model.presented = true
        model.solidBackdrop = true
        let gridSize = CGSize(width: 1120, height: 640)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            model.query = ""
            model.highlighted = 2
            write(TabGridView(model: model), size: gridSize, appearance: appearance, to: output, name: "grid-\(name)")
        }

        // Storyboard frames for the demo GIF: move through the grid, then search.
        var frame = 0
        func shot() {
            write(TabGridView(model: model), size: gridSize, appearance: .aqua, to: output,
                  name: String(format: "frame-%02d", frame))
            frame += 1
        }
        model.query = ""
        for i in [2, 3, 7, 6, 5] {
            model.highlighted = i
            shot()
        }
        for q in ["p", "ph", "pho", "photos"] {
            model.query = q
            model.highlighted = 0
            shot()
        }
        model.query = ""
        model.highlighted = 2
        shot()

        // Preview mode: cards show the documents themselves.
        let documents = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["pdf", "jpg"].contains($0.pathExtension) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(2)
        }
        for url in documents { _ = waitFor { await PreviewLoader.shared.loadDocument(url) } }
        model.app = .preview
        model.query = ""
        model.highlighted = 1
        model.tabs = documents.enumerated().map { i, url in
            FinderTab(id: i, title: url.lastPathComponent, url: url, isActive: i == 1, button: nil)
        }
        write(TabGridView(model: model), size: CGSize(width: 1120, height: 470), appearance: .aqua,
              to: output, name: "preview-light")

        write(SettingsView(), size: nil, appearance: .aqua, to: output, name: "settings-light")
        write(SettingsView(), size: nil, appearance: .darkAqua, to: output, name: "settings-dark")
    }

    /// Hosts the view in an offscreen window and draws it at 2× into a PNG.
    private static func write<V: View>(_ view: V, size: CGSize?, appearance: NSAppearance.Name, to dir: URL, name: String) {
        let host = NSHostingView(rootView: view)
        let fitted = size ?? host.fittingSize
        let window = NSWindow(contentRect: CGRect(x: -30000, y: -30000, width: fitted.width, height: fitted.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = size == nil ? .windowBackgroundColor : .clear
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fitted.width * 2), pixelsHigh: Int(fitted.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = fitted
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        window.orderOut(nil)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Runs async work to completion from synchronous code, keeping the main run loop alive.
    private static func waitFor<T>(_ work: @escaping () async -> T) -> T {
        var result: T?
        Task { result = await work() }
        while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return result!
    }
}
