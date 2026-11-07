import AppKit
import RazerCore
import SwiftUI

/// Whether the app shows in the Dock. Cmd+Q closes the windows and leaves only the menu bar item
/// running, like iStat Menus; opening a window brings the Dock icon back.
enum DockPresence {
    static func hideToMenuBar() {
        NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
        // Hands focus to the previous app; an accessory app would otherwise stay active.
        NSApp.hide(nil)
    }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running the bare SwiftPM binary (not the .app bundle) starts as a background process.
        if ProbeRunner.requested {
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { $0.orderOut(nil) }
            Task { @MainActor in await ProbeRunner.run() }
            return
        }
        if let directory = SnapshotRenderer.outputDirectory {
            // Stay out of the Dock and off screen while rendering.
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { $0.orderOut(nil) }
            Task { @MainActor in await SnapshotRenderer.run(into: directory) }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching the app again from Finder or Spotlight while it sits in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockPresence.show()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct OpenSynapseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OpenSynapse", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            // Only the menu command changes: logout, shutdown and the Dock's Quit still quit.
            CommandGroup(replacing: .appTermination) {
                Button("退出到菜单栏") { DockPresence.hideToMenuBar() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("重新扫描设备") { Task { await model.rescan() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: "computermouse")
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if app.availableItems.isEmpty {
            Text("没有可控制的雷蛇设备")
        }
        ForEach(app.availableItems) { item in
            DeviceQuickMenu(item: item) {
                app.selection = .device(item.id)
                showMainWindow()
            }
        }
        Divider()
        Button("重新扫描") { Task { await app.rescan() } }
        Button("打开主窗口") { showMainWindow() }
        Divider()
        Button("完全退出") { NSApp.terminate(nil) }
    }

    private func showMainWindow() {
        DockPresence.show()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
