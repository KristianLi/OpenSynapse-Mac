import AppKit
import SwiftUI

/// `OpenSynapse --snapshot <dir>` renders every page with the demo devices into PNG files
/// from an offscreen window, then quits. Used to review the layout without a display.
@MainActor
enum SnapshotRenderer {
    static var outputDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(into directory: URL, appearance: NSAppearance.Name = .aqua) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(forceDemo: !CommandLine.arguments.contains("--real"))
        model.headlessOwner = true
        let deadline = Date().addingTimeInterval(20)
        while (model.items.isEmpty || model.scanning) && Date() < deadline {
            if model.items.isEmpty && !model.scanning && model.lastScan != nil { await model.rescan() }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        print("snapshot: \(model.items.count) device page(s), interfaces=\(model.rawInterfaces.count), lastScan=\(String(describing: model.lastScan)), demo=\(model.demoMode)")
        try? await Task.sleep(nanoseconds: 500_000_000)

        var pages: [(String, SidebarSelection)] = [("00-overview", .overview)]
        for (index, item) in model.items.enumerated() {
            let name = item.page.title.replacingOccurrences(of: " ", with: "-")
            pages.append((String(format: "%02d-%@", index + 1, name), .device(item.id)))
        }
        pages.append(("99-diagnostics", .diagnostics))

        for (name, selection) in pages {
            model.selection = selection
            let view = ContentView().environment(model)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 1700),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            window.orderFront(nil)
            try? await Task.sleep(nanoseconds: 700_000_000)
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = directory.appendingPathComponent("\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
            }
            window.orderOut(nil)
        }
        NSApp.terminate(nil)
    }
}
