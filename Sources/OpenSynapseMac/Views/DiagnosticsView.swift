import AppKit
import RazerCore
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var app
    @State private var filter = ""
    @State private var showInterfaces = false

    private var entries: [DiagnosticEntry] {
        _ = app.logRevision
        let all = DiagnosticLog.shared.entries
        guard !filter.isEmpty else { return all }
        return all.filter { $0.tag.localizedCaseInsensitiveContains(filter) || $0.message.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("诊断日志", "Diagnostics")).font(.title2.weight(.semibold))
                Spacer()
                TextField(L("筛选", "Filter"), text: $filter).textFieldStyle(.roundedBorder).frame(width: 200)
                Picker("", selection: $showInterfaces) {
                    Text(L("通信记录", "Traffic log")).tag(false)
                    Text(L("HID 接口", "HID interfaces")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Button(L("复制全部", "Copy All")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(showInterfaces ? interfaceText : DiagnosticLog.shared.exportText(), forType: .string)
                }
                Button(L("导出…", "Export…")) { export() }
                Button(L("清空", "Clear"), role: .destructive) { DiagnosticLog.shared.clear() }
                    .disabled(showInterfaces)
            }
            if showInterfaces {
                List(app.rawInterfaces) { item in
                    Text(item.summary).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .overlay {
                    if app.rawInterfaces.isEmpty {
                        ContentUnavailableView(L("没有雷蛇 HID 接口", "No Razer HID interfaces"), systemImage: "cable.connector.slash",
                                               description: Text(L("插入设备后会自动出现在这里。", "Devices appear here automatically when plugged in.")))
                    }
                }
            } else {
                List(Array(entries.reversed())) { (entry: DiagnosticEntry) in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.date.formatted(.dateTime.hour().minute().second()))
                            .foregroundStyle(.secondary)
                        Text(entry.tag).foregroundStyle(.razer).frame(width: 130, alignment: .leading).lineLimit(1)
                        Text(entry.message).textSelection(.enabled)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView(L("暂无记录", "No entries yet"), systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
        .pagePadding()
    }

    private var interfaceText: String { app.rawInterfaces.map(\.summary).joined(separator: "\n") }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenSynapseMac-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = DiagnosticLog.shared.exportText() + L("\n\n# HID 接口\n", "\n\n# HID interfaces\n") + interfaceText
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        Form {
            Section(L("语言", "Language")) {
                Picker(L("界面语言", "Interface language"), selection: Bindable(Localization.shared).language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Text(L("切换后立即生效；系统提供的菜单项（隐藏、服务等）在重新打开应用后切换。",
                       "Takes effect at once; menu items supplied by macOS (Hide, Services…) switch after the app is reopened."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("通信方式", "Connection")) {
                Picker(L("通道", "Channel"), selection: $app.transportPreference) {
                    ForEach(TransportPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(L("HID 特性报告与 Windows 版相同；USB 控制传输是 OpenRazer 在 Linux 上使用的通道，不需要“输入监控”权限。更改后会重新扫描。", "HID feature reports are what the Windows version uses; USB control transfers are the channel OpenRazer uses on Linux and need no Input Monitoring permission. Changing this rescans."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("演示", "Demo")) {
                Toggle(L("演示模式（用模拟设备代替真实硬件）", "Demo mode (simulated devices instead of real hardware)"), isOn: $app.demoMode)
            }
            Section(L("关于", "About")) {
                LabeledContent(L("版本", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版", "Development build"))
                LabeledContent(L("设备目录", "Device catalog"), value: "OpenRazer \(String(OpenRazerCatalog.sourceCommit.prefix(10)))")
                Text(L("本应用移植自 OpenSynapse（MIT 许可），与 Razer Inc. 无关联。Razer 及相关产品名称为其各自所有者的商标。", "This app is a port of OpenSynapse (MIT licence) and is not affiliated with Razer Inc. Razer and related product names are trademarks of their respective owners."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
    }
}
