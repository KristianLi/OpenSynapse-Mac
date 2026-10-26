import AppKit
import RazerCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.selection) {
                Label("概览", systemImage: "square.grid.2x2").tag(SidebarSelection.overview)
                Section("设备") {
                    if app.availableItems.isEmpty {
                        Text(app.scanning ? "正在扫描…" : "没有可控制的设备")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(app.availableItems) { item in
                        DeviceRow(page: item.page).tag(SidebarSelection.device(item.id))
                    }
                }
                if !app.unavailableItems.isEmpty {
                    Section("未接管") {
                        ForEach(app.unavailableItems) { item in
                            DeviceRow(page: item.page).tag(SidebarSelection.device(item.id))
                        }
                    }
                }
                Section("工具") {
                    Label("诊断日志", systemImage: "list.bullet.rectangle").tag(SidebarSelection.diagnostics)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                if app.demoMode {
                    Label("演示模式：显示的是模拟设备", systemImage: "theatermasks")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                }
            }
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await app.rescan() }
                } label: {
                    if app.scanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("重新扫描", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help("重新扫描雷蛇设备")
                .disabled(app.scanning)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .device(let id)?:
            if let item = app.item(id) {
                DevicePageView(page: item.page).id(item.id)
            } else {
                OverviewView()
            }
        case .diagnostics?:
            DiagnosticsView()
        default:
            OverviewView()
        }
    }
}

struct DeviceRow: View {
    let page: DevicePage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: page.symbol)
                .foregroundStyle(page.isAvailable ? .razer : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title).lineLimit(1)
                Text(String(format: "1532:%04X", page.productId)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = page.batteryPercent {
                Text("\(battery)%").font(.caption).monospacedDigit().foregroundStyle(battery <= 15 ? .red : .secondary)
            }
        }
    }
}

struct DevicePageView: View {
    let page: DevicePage

    var body: some View {
        switch page {
        case .openRazer(let model): OpenRazerView(model: model)
        case .keyboard(let model): KeyboardView(model: model)
        case .audio(let model): AudioView(model: model)
        case .chroma(let model): ChromaView(model: model)
        case .kraken(let model): KrakenView(model: model)
        case .blackShark(let model): BlackSharkView(model: model)
        case .lampArray(let model): LampArrayView(model: model)
        case .unavailable(let device): UnavailableView(device: device)
        }
    }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.razer)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenSynapse for Mac").font(.largeTitle.weight(.semibold))
                        Text("不用雷蛇官方软件，在 macOS 上直接控制雷蛇外设。移植自 OpenSynapse（Windows）。")
                            .foregroundStyle(.secondary)
                    }
                }
                CardGrid {
                    Card(title: "已连接", symbol: "cable.connector") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(app.availableItems.count)").font(.system(size: 34, weight: .semibold)).monospacedDigit()
                            Text("台可控制").foregroundStyle(.secondary)
                            Spacer()
                            if !app.unavailableItems.isEmpty {
                                Text("\(app.unavailableItems.count) 台未接管").foregroundStyle(.orange)
                            }
                        }
                        ForEach(app.availableItems) { item in
                            Button {
                                app.selection = .device(item.id)
                            } label: {
                                DeviceRow(page: item.page).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if let date = app.lastScan {
                            Text("上次扫描：\(date.formatted(date: .omitted, time: .standard))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card(title: "支持范围", symbol: "checklist") {
                        InfoRow(label: "可识别的型号", value: "\(app.recognisedProducts) 个 USB ID")
                        InfoRow(label: "OpenRazer 目录", value: "\(app.catalogCount) 款（鼠标、键盘、笔记本、配件）")
                        InfoRow(label: "协议 25 键盘", value: "\(ProductLists.keyboards25.count) 款")
                        InfoRow(label: "耳机 / 音箱 / 麦克风", value: "\(ProductLists.headsetAudio.count) 款")
                        InfoRow(label: "Chroma 灯光配件", value: "\(ProductLists.chromaStandard.count) 款")
                        InfoRow(label: "Kraken 灯光 / 64 字节协议耳机", value: "\(ProductLists.kraken.count) 款 / \(1 + ProductLists.blackSharkProtocolHeadsets.count) 款")
                        InfoRow(label: "HID LampArray 灯光", value: "自动识别")
                    }
                    Card(title: "权限", symbol: "lock.shield") {
                        HStack {
                            Image(systemName: app.inputMonitoringGranted ? "checkmark.seal.fill" : "exclamationmark.circle")
                                .foregroundStyle(app.inputMonitoringGranted ? .razer : .orange)
                            Text(app.inputMonitoringGranted ? "已获得“输入监控”权限" : "未获得“输入监控”权限")
                        }
                        Text("键盘的 HID 接口需要“输入监控”权限才能打开。没有权限时，应用会自动改用 USB 控制传输（与 OpenRazer 相同的通道），大多数设备仍可正常使用。")
                            .font(.callout).foregroundStyle(.secondary)
                        if !app.inputMonitoringGranted {
                            HStack {
                                Spacer()
                                Button("请求权限…") { app.requestInputMonitoring() }
                            }
                        }
                    }
                    Card(title: "使用提示", symbol: "lightbulb") {
                        Text("• 设备插入或拔出后会自动重新扫描。")
                        Text("• 只会显示该型号目录里声明、且接口确认可用的控制项。")
                        Text("• 如果某个设备“未接管”，请关闭其他雷蛇控制软件后点工具栏的重新扫描。")
                        Text("• 没有设备时，可以在“设置”里打开演示模式预览界面。")
                    }
                    .font(.callout)
                }
            }
            .pagePadding()
        }
    }
}
