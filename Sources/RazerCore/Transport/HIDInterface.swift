import Foundation
import IOKit
import IOKit.hid

/// One HID interface (top-level collection) of a Razer USB device, as macOS enumerates it.
public final class HIDInterface: @unchecked Sendable, Identifiable {
    public let device: IOHIDDevice?
    public let vendorId: UInt16
    public let productId: UInt16
    public let productName: String?
    public let manufacturer: String?
    public let serialNumber: String?
    public let locationId: UInt32
    public let usagePage: UInt32
    public let usage: UInt32
    public let maxFeatureReportSize: Int
    public let maxOutputReportSize: Int
    public let maxInputReportSize: Int
    public let transport: String?
    public let registryId: UInt64
    public let interfaceNumber: Int?
    /// Set only for simulated (demo) interfaces.
    public let simulated: SimulatedDevice?

    public var id: UInt64 { registryId }

    /// Interfaces of one physical device share the USB location ID.
    public var physicalKey: String {
        locationId != 0 ? String(format: "loc:%08X:%04X", locationId, productId)
            : "reg:\(registryId)"
    }

    /// The 90-byte Razer control collection. Windows reports 91 (with report ID 0), macOS 90.
    public var hasRazerFeatureReport: Bool { maxFeatureReportSize == 90 || maxFeatureReportSize == 91 }

    public var usageText: String { String(format: "0x%04X:0x%04X", usagePage, usage) }

    public var summary: String {
        "pid=\(String(format: "%04X", productId)) usage=\(usageText) if=\(interfaceNumber.map(String.init) ?? "?") "
            + "feature=\(maxFeatureReportSize) out=\(maxOutputReportSize) in=\(maxInputReportSize) "
            + "transport=\(transport ?? "?") name='\(productName ?? "")'"
    }

    init(device: IOHIDDevice) {
        self.device = device
        vendorId = UInt16(truncatingIfNeeded: Self.int(device, kIOHIDVendorIDKey) ?? 0)
        productId = UInt16(truncatingIfNeeded: Self.int(device, kIOHIDProductIDKey) ?? 0)
        productName = Self.string(device, kIOHIDProductKey)
        manufacturer = Self.string(device, kIOHIDManufacturerKey)
        serialNumber = Self.string(device, kIOHIDSerialNumberKey)
        locationId = UInt32(truncatingIfNeeded: Self.int(device, kIOHIDLocationIDKey) ?? 0)
        usagePage = UInt32(truncatingIfNeeded: Self.int(device, kIOHIDPrimaryUsagePageKey) ?? 0)
        usage = UInt32(truncatingIfNeeded: Self.int(device, kIOHIDPrimaryUsageKey) ?? 0)
        maxFeatureReportSize = Self.int(device, kIOHIDMaxFeatureReportSizeKey) ?? 0
        maxOutputReportSize = Self.int(device, kIOHIDMaxOutputReportSizeKey) ?? 0
        maxInputReportSize = Self.int(device, kIOHIDMaxInputReportSizeKey) ?? 0
        transport = Self.string(device, kIOHIDTransportKey)
        let service = IOHIDDeviceGetService(device)
        var entryId: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryId)
        registryId = entryId
        interfaceNumber = Self.searchParents(service, "bInterfaceNumber")
        simulated = nil
    }

    init(simulated: SimulatedDevice, usagePage: UInt32, usage: UInt32, feature: Int, output: Int, input: Int, registryId: UInt64) {
        device = nil
        vendorId = razerVendorId
        productId = simulated.productId
        productName = simulated.name
        manufacturer = "Razer（模拟）"
        serialNumber = simulated.serial
        locationId = 0xD000_0000 | UInt32(simulated.productId)
        self.usagePage = usagePage
        self.usage = usage
        maxFeatureReportSize = feature
        maxOutputReportSize = output
        maxInputReportSize = input
        transport = "Simulated"
        self.registryId = registryId
        interfaceNumber = 0
        self.simulated = simulated
    }

    private static func int(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func searchParents(_ service: io_service_t, _ key: String) -> Int? {
        let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        return (value as? NSNumber)?.intValue
    }
}

/// Watches Razer HID interfaces. The manager is never opened: opening it would open every
/// matched device (including keyboards, which needs Input Monitoring) just to enumerate.
public final class HIDMonitor: @unchecked Sendable {
    public static let didChange = Notification.Name("OpenSynapseMac.HIDMonitor.didChange")

    private let manager: IOHIDManager
    private var debounce: DispatchWorkItem?
    private let lock = NSLock()
    /// Devices reported by the matching callback. IOHIDManagerCopyDevices only returns what the
    /// run loop has already matched, so polling it right after launch can come back empty.
    private var devices: [UInt64: IOHIDDevice] = [:]

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Int(razerVendorId)] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().update(device, present: true)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().update(device, present: false)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func update(_ device: IOHIDDevice, present: Bool) {
        var entryId: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryId)
        lock.lock()
        devices[entryId] = present ? device : nil
        lock.unlock()
        scheduleChange()
    }

    public func interfaces() -> [HIDInterface] {
        lock.lock()
        var known = Array(devices.values)
        lock.unlock()
        if known.isEmpty, let copied = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            known = Array(copied)
        }
        return known.map(HIDInterface.init(device:))
            .filter { $0.vendorId == razerVendorId }
            .sorted { ($0.productId, $0.registryId) < ($1.productId, $1.registryId) }
    }

    private func scheduleChange() {
        debounce?.cancel()
        let item = DispatchWorkItem {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    /// Input Monitoring state. Opening a keyboard's HID interface needs it; mice and vendor
    /// collections do not. The USB control path never needs it.
    public static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
