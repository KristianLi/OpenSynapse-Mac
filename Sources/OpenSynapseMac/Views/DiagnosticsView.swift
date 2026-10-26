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
                Text("诊断日志").font(.title2.weight(.semibold))
                Spacer()
                TextField("筛选", text: $filter).textFieldStyle(.roundedBorder).frame(width: 200)
                Picker("", selection: $showInterfaces) {
                    Text("通信记录").tag(false)
                    Text("HID 接口").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Button("复制全部") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(showInterfaces ? interfaceText : DiagnosticLog.shared.exportText(), forType: .string)
                }
                Button("导出…") { export() }
                Button("清空", role: .destructive) { DiagnosticLog.shared.clear() }
                    .disabled(showInterfaces)
            }
            if showInterfaces {
                List(app.rawInterfaces) { item in
                    Text(item.summary).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .overlay {
                    if app.rawInterfaces.isEmpty {
                        ContentUnavailableView("没有雷蛇 HID 接口", systemImage: "cable.connector.slash",
                                               description: Text("插入设备后会自动出现在这里。"))
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
                        ContentUnavailableView("暂无记录", systemImage: "list.bullet.rectangle")
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
        let text = DiagnosticLog.shared.exportText() + "\n\n# HID 接口\n" + interfaceText
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section("通信方式") {
                Picker("通道", selection: $app.transportPreference) {
                    ForEach(TransportPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text("HID 特性报告与 Windows 版相同；USB 控制传输是 OpenRazer 在 Linux 上使用的通道，不需要“输入监控”权限。更改后会重新扫描。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("演示") {
                Toggle("演示模式（用模拟设备代替真实硬件）", isOn: $app.demoMode)
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                LabeledContent("设备目录", value: "OpenRazer \(String(OpenRazerCatalog.sourceCommit.prefix(10)))")
                Text("本应用移植自 OpenSynapse（MIT 许可），与 Razer Inc. 无关联。Razer 及相关产品名称为其各自所有者的商标。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
