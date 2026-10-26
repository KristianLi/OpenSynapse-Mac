import AppKit
import Observation
import RazerCore
import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case device(String)
    case diagnostics
}

/// One row in the sidebar: a physical device and the page model that drives it.
@MainActor
final class DeviceItem: Identifiable {
    let id: String
    let fingerprint: String
    let page: DevicePage

    init(id: String, fingerprint: String, page: DevicePage) {
        self.id = id
        self.fingerprint = fingerprint
        self.page = page
    }
}

@MainActor
enum DevicePage {
    case openRazer(OpenRazerModel)
    case keyboard(KeyboardModel)
    case audio(AudioModel)
    case chroma(ChromaModel)
    case kraken(KrakenModel)
    case blackShark(BlackSharkModel)
    case lampArray(LampArrayModel)
    case unavailable(UnavailableDevice)

    var title: String {
        switch self {
        case .openRazer(let model): model.device.definition.displayName
        case .keyboard(let model): model.device.name
        case .audio(let model): model.device.name
        case .chroma(let model): model.device.name
        case .kraken(let model): model.device.model.name
        case .blackShark(let model): model.device.name
        case .lampArray(let model): model.device.name
        case .unavailable(let device): device.name
        }
    }

    var symbol: String {
        switch self {
        case .openRazer(let model): model.device.definition.category.symbolName
        case .keyboard: DeviceCategory.keyboard.symbolName
        case .audio(let model): model.device.category.symbolName
        case .chroma(let model): model.device.category.symbolName
        case .kraken, .blackShark: DeviceCategory.headset.symbolName
        case .lampArray: "lightbulb.led"
        case .unavailable(let device): device.category?.symbolName ?? "questionmark.circle"
        }
    }

    var productId: UInt16 {
        switch self {
        case .openRazer(let model): model.device.definition.productId
        case .keyboard(let model): model.device.productId
        case .audio(let model): model.device.productId
        case .chroma(let model): model.device.productId
        case .kraken(let model): model.device.productId
        case .blackShark(let model): model.device.productId
        case .lampArray(let model): model.device.productId
        case .unavailable(let device): device.productId
        }
    }

    var batteryPercent: Int? {
        switch self {
        case .openRazer(let model): model.state.batteryPercent
        case .keyboard(let model): model.state.batteryPercent
        case .audio(let model): model.state.batteryPercent
        case .chroma(let model): model.state.batteryPercent
        case .blackShark(let model): model.state.batteryPercent
        default: nil
        }
    }

    var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    func load() async {
        switch self {
        case .openRazer(let model): await model.load()
        case .keyboard(let model): await model.load()
        case .audio(let model): await model.load()
        case .chroma(let model): await model.load()
        case .kraken: break
        case .blackShark(let model): await model.load()
        case .lampArray: break
        case .unavailable: break
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var items: [DeviceItem] = []
    var selection: SidebarSelection? = .overview
    var scanning = false
    var lastScan: Date?
    var inputMonitoringGranted = HIDMonitor.inputMonitoringGranted
    var logRevision = 0
    var rawInterfaces: [HIDInterface] = []
    /// Set by the snapshot renderer for the one model allowed to scan in a headless run.
    @ObservationIgnored var headlessOwner = false
    @ObservationIgnored private var rescanPending = false

    var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "demoMode")
            items = []
            Task { await rescan() }
        }
    }

    var transportPreference: TransportPreference {
        didSet {
            UserDefaults.standard.set(transportPreference.rawValue, forKey: "transportPreference")
            items = []
            Task { await rescan() }
        }
    }

    let recognisedProducts = ProductLists.recognisedProductCount(catalog: .builtIn)
    let catalogCount = OpenRazerCatalog.builtIn.devices.count

    @ObservationIgnored private let monitor = HIDMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var batteryTimer: Timer?

    init(forceDemo: Bool = false) {
        demoMode = forceDemo || UserDefaults.standard.bool(forKey: "demoMode")
        transportPreference = TransportPreference(rawValue: UserDefaults.standard.string(forKey: "transportPreference") ?? "")
            ?? .automatic
        observers.append(NotificationCenter.default.addObserver(forName: HIDMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.rescan() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: DiagnosticLog.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.logRevision += 1 }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.inputMonitoringGranted = HIDMonitor.inputMonitoringGranted }
        })
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBatteries() }
        }
        Task { await rescan() }
    }

    var availableItems: [DeviceItem] { items.filter { $0.page.isAvailable } }
    var unavailableItems: [DeviceItem] { items.filter { !$0.page.isAvailable } }

    func item(_ id: String) -> DeviceItem? { items.first { $0.id == id } }

    func rescan() async {
        // Headless --probe/--snapshot runs drive devices themselves; stay off the hardware.
        guard demoMode || headlessOwner || !(ProbeRunner.requested || SnapshotRenderer.outputDirectory != nil) else { return }
        guard !scanning else {
            // A device arrived mid-scan; scan again once this one finishes instead of dropping it.
            rescanPending = true
            return
        }
        scanning = true
        defer {
            scanning = false
            lastScan = Date()
            if rescanPending {
                rescanPending = false
                Task { await rescan() }
            }
        }
        let interfaces = demoMode ? DeviceDiscovery.simulatedInterfaces() : monitor.interfaces()
        rawInterfaces = interfaces
        DiagnosticLog.shared.write("scan", "发现 \(interfaces.count) 个雷蛇 HID 接口\(demoMode ? "（演示模式）" : "")")
        var next: [DeviceItem] = []
        var fresh: [DeviceItem] = []
        for group in DeviceDiscovery.groups(interfaces) {
            if let existing = items.first(where: { $0.id == group.key && $0.fingerprint == group.fingerprint }) {
                next.append(existing)
                continue
            }
            let resolved = await DeviceDiscovery.resolve(group, preference: transportPreference)
            let item = DeviceItem(id: group.key, fingerprint: group.fingerprint, page: Self.page(for: resolved))
            next.append(item)
            fresh.append(item)
        }
        items = next
        if case .device(let id)? = selection, item(id) == nil {
            selection = .overview
        }
        for item in fresh {
            await item.page.load()
        }
    }

    func refreshBatteries() async {
        for item in items {
            switch item.page {
            case .openRazer(let model) where model.device.has(.batteryRead): await model.refreshBattery()
            case .blackShark(let model): await model.load()
            default: break
            }
        }
    }

    func requestInputMonitoring() {
        HIDMonitor.requestInputMonitoring()
        inputMonitoringGranted = HIDMonitor.inputMonitoringGranted
        if !inputMonitoringGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func page(for device: DiscoveredDevice) -> DevicePage {
        switch device {
        case .openRazer(let device): .openRazer(OpenRazerModel(device: device))
        case .keyboard(let device): .keyboard(KeyboardModel(device: device))
        case .audio(let device, let lighting): .audio(AudioModel(device: device, lighting: lighting.map(KrakenModel.init)))
        case .chroma(let device): .chroma(ChromaModel(device: device))
        case .kraken(let device): .kraken(KrakenModel(device: device))
        case .blackShark(let device, let lighting): .blackShark(BlackSharkModel(device: device, lighting: lighting.map(LampArrayModel.init)))
        case .lampArray(let device): .lampArray(LampArrayModel(device: device))
        case .unavailable(let device): .unavailable(device)
        }
    }
}
