import AppKit
import RazerCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.selection) {
                Label(L("概览", "Overview"), systemImage: "square.grid.2x2").tag(SidebarSelection.overview)
                Section(L("设备", "Devices")) {
                    if app.availableItems.isEmpty {
                        Text(app.scanning ? L("正在扫描…", "Scanning…") : L("没有可控制的设备", "No controllable devices"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(app.availableItems) { item in
                        DeviceRow(page: item.page).tag(SidebarSelection.device(item.id))
                    }
                }
                if !app.unavailableItems.isEmpty {
                    Section(L("未接管", "Not controlled")) {
                        ForEach(app.unavailableItems) { item in
                            DeviceRow(page: item.page).tag(SidebarSelection.device(item.id))
                        }
                    }
                }
                Section(L("工具", "Tools")) {
                    Label(L("诊断日志", "Diagnostics"), systemImage: "list.bullet.rectangle").tag(SidebarSelection.diagnostics)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                if app.demoMode {
                    Label(L("演示模式：显示的是模拟设备", "Demo mode: showing simulated devices"), systemImage: "theatermasks")
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
                        Label(L("重新扫描", "Rescan"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help(L("重新扫描雷蛇设备", "Rescan Razer devices"))
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
                        Text(L("不用雷蛇官方软件，在 macOS 上直接控制雷蛇外设。移植自 OpenSynapse（Windows）。", "Control Razer peripherals on macOS without Razer's software. Ported from OpenSynapse (Windows)."))
                            .foregroundStyle(.secondary)
                    }
                }
                CardGrid {
                    Card(title: L("已连接", "Connected"), symbol: "cable.connector") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(app.availableItems.count)").font(.system(size: 34, weight: .semibold)).monospacedDigit()
                            Text(L("台可控制", "controllable")).foregroundStyle(.secondary)
                            Spacer()
                            if !app.unavailableItems.isEmpty {
                                Text(L("\(app.unavailableItems.count) 台未接管", "\(app.unavailableItems.count) not controlled")).foregroundStyle(.orange)
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
                            Text(L("上次扫描：\(date.formatted(date: .omitted, time: .standard))", "Last scan: \(date.formatted(date: .omitted, time: .standard))"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card(title: L("支持范围", "Coverage"), symbol: "checklist") {
                        InfoRow(label: L("可识别的型号", "Recognised models"), value: L("\(app.recognisedProducts) 个 USB ID", "\(app.recognisedProducts) USB IDs"))
                        InfoRow(label: L("OpenRazer 目录", "OpenRazer catalog"), value: L("\(app.catalogCount) 款（鼠标、键盘、笔记本、配件）", "\(app.catalogCount) models (mice, keyboards, laptops, accessories)"))
                        InfoRow(label: L("协议 25 键盘", "Protocol 25 keyboards"), value: L("\(ProductLists.keyboards25.count) 款", "\(ProductLists.keyboards25.count) models"))
                        InfoRow(label: L("耳机 / 音箱 / 麦克风", "Headsets / speakers / microphones"), value: L("\(ProductLists.headsetAudio.count) 款", "\(ProductLists.headsetAudio.count) models"))
                        InfoRow(label: L("Chroma 灯光配件", "Chroma lighting accessories"), value: L("\(ProductLists.chromaStandard.count) 款", "\(ProductLists.chromaStandard.count) models"))
                        InfoRow(label: L("Kraken 灯光 / 64 字节协议耳机", "Kraken lighting / 64-byte protocol headsets"), value: L("\(ProductLists.kraken.count) 款 / \(1 + ProductLists.blackSharkProtocolHeadsets.count) 款", "\(ProductLists.kraken.count) / \(1 + ProductLists.blackSharkProtocolHeadsets.count) models"))
                        InfoRow(label: L("HID LampArray 灯光", "HID LampArray lighting"), value: L("自动识别", "Detected automatically"))
                    }
                    Card(title: L("权限", "Permissions"), symbol: "lock.shield") {
                        HStack {
                            Image(systemName: app.inputMonitoringGranted ? "checkmark.seal.fill" : "exclamationmark.circle")
                                .foregroundStyle(app.inputMonitoringGranted ? .razer : .orange)
                            Text(app.inputMonitoringGranted ? L("已获得“输入监控”权限", "Input Monitoring permission granted") : L("未获得“输入监控”权限", "Input Monitoring permission not granted"))
                        }
                        Text(L("键盘的 HID 接口需要“输入监控”权限才能打开。没有权限时，应用会自动改用 USB 控制传输（与 OpenRazer 相同的通道），大多数设备仍可正常使用。", "Keyboard HID interfaces need the Input Monitoring permission to open. Without it, the app switches to USB control transfers (the same channel OpenRazer uses), and most devices still work."))
                            .font(.callout).foregroundStyle(.secondary)
                        if !app.inputMonitoringGranted {
                            HStack {
                                Spacer()
                                Button(L("请求权限…", "Request Permission…")) { app.requestInputMonitoring() }
                            }
                        }
                    }
                    Card(title: L("使用提示", "Tips"), symbol: "lightbulb") {
                        Text(L("• 设备插入或拔出后会自动重新扫描。", "• Devices are rescanned automatically when plugged in or removed."))
                        Text(L("• 只会显示该型号目录里声明、且接口确认可用的控制项。", "• Only controls that the model's catalog entry declares and that answer on its interface are shown."))
                        Text(L("• 如果某个设备“未接管”，请关闭其他雷蛇控制软件后点工具栏的重新扫描。", "• If a device is “not controlled”, quit other Razer software and press Rescan in the toolbar."))
                        Text(L("• 没有设备时，可以在“设置”里打开演示模式预览界面。", "• With no device attached, turn on demo mode in Settings to preview the interface."))
                    }
                    .font(.callout)
                }
            }
            .pagePadding()
        }
    }
}
