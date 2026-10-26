import AppKit
import RazerCore
import SwiftUI

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
            Button {
                app.selection = .device(item.id)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                if let battery = item.page.batteryPercent {
                    Text("\(item.page.title)  \(battery)%")
                } else {
                    Text(item.page.title)
                }
            }
        }
        Divider()
        Button("重新扫描") { Task { await app.rescan() } }
        Button("打开主窗口") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
