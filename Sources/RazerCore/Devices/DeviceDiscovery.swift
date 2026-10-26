import Foundation

/// A Razer device that is attached but could not be driven, with the reason.
public struct UnavailableDevice: Sendable {
    public let productId: UInt16
    public let name: String
    public let category: DeviceCategory?
    public let recognised: Bool
    public let reason: String
    public let interfaces: [String]
}

public enum DiscoveredDevice: @unchecked Sendable {
    case openRazer(OpenRazerDevice)
    case keyboard(Keyboard25Device)
    case audio(HeadsetAudioDevice, lighting: KrakenDevice?)
    case chroma(ChromaDevice)
    case kraken(KrakenDevice)
    case blackShark(BlackSharkDevice, lighting: LampArrayDevice?)
    case lampArray(LampArrayDevice)
    case unavailable(UnavailableDevice)

    public var productId: UInt16 {
        switch self {
        case .openRazer(let device): device.definition.productId
        case .keyboard(let device): device.productId
        case .audio(let device, _): device.productId
        case .chroma(let device): device.productId
        case .kraken(let device): device.productId
        case .blackShark(let device, _): device.productId
        case .lampArray(let device): device.productId
        case .unavailable(let device): device.productId
        }
    }
}

/// One physical USB device: all HID interfaces that share a location ID.
public struct InterfaceGroup: Sendable {
    public let key: String
    public let productId: UInt16
    public let interfaces: [HIDInterface]

    /// Registry IDs identify this exact enumeration; a re-plugged device gets new ones.
    public var fingerprint: String { interfaces.map { String($0.registryId) }.sorted().joined(separator: ",") }
}

public enum DeviceDiscovery {
    public static func groups(_ interfaces: [HIDInterface]) -> [InterfaceGroup] {
        Dictionary(grouping: interfaces, by: \.physicalKey)
            .map { InterfaceGroup(key: $0.key, productId: $0.value[0].productId, interfaces: $0.value) }
            .sorted { ($0.productId, $0.key) < ($1.productId, $1.key) }
    }

    public static func resolve(_ group: InterfaceGroup, preference: TransportPreference,
                               catalog: OpenRazerCatalog = .builtIn) async -> DiscoveredDevice {
        let pid = group.productId
        let tagPid = String(format: "%04X", pid)
        let summaries = group.interfaces.map(\.summary)
        for line in summaries {
            DiagnosticLog.shared.write("scan-\(tagPid)", "接口 \(line)")
        }
        let featureInterfaces = group.interfaces.filter(\.hasRazerFeatureReport)

        func unavailable(_ name: String, _ category: DeviceCategory?, recognised: Bool, _ reason: String) -> DiscoveredDevice {
            DiagnosticLog.shared.write("scan-\(tagPid)", "未能接管：\(reason)")
            return .unavailable(UnavailableDevice(productId: pid, name: name, category: category, recognised: recognised,
                                                  reason: reason, interfaces: summaries))
        }

        // BlackShark V3 Pro: its own 64-byte output report channel on FF13/FF14.
        let blackSharkCandidates = group.interfaces.filter { item in
            // macOS reports one HID device per USB interface, so on a composite headset the
            // vendor collection can sit behind a consumer-control primary usage.
            let vendorPage = (item.usagePage == 0xFF13 || item.usagePage == 0xFF14) && item.usage == 0x01
            return item.maxOutputReportSize >= 63
                && ((vendorPage && ((item.productName?.localizedCaseInsensitiveContains("BlackShark") ?? false)
                    || ProductLists.blackSharkObserved.contains(pid)))
                    || ProductLists.blackSharkProtocolHeadsets[pid] != nil)
        }
        if let chosen = blackSharkCandidates.first(where: { $0.usagePage == 0xFF14 }) ?? blackSharkCandidates.first {
            let channel = ReportChannel(interface: chosen, tag: "blackshark-\(tagPid)")
            let headset = BlackSharkDevice(productId: pid, channel: channel)
            let lighting = await lampArray(group, pid: pid, name: headset.name, reuse: channel)
            return .blackShark(headset, lighting: lighting)
        }

        if let definition = catalog.find(productId: pid) {
            guard !featureInterfaces.isEmpty else {
                return unavailable(definition.displayName, definition.category, recognised: true,
                                   "没有找到 90 字节的 HID 控制接口")
            }
            var lastError = "没有可用于探测的只读命令"
            for candidate in featureInterfaces {
                let endpoint = FeatureEndpoint(interface: candidate, preference: preference, tag: "openrazer-\(tagPid)")
                do {
                    if try await OpenRazerDevice.probe(definition, endpoint: endpoint) {
                        DiagnosticLog.shared.write("scan-\(tagPid)", "已解析控制接口 \(candidate.usageText) 经 \(endpoint.pathDescription)")
                        let adapted = await OpenRazerDevice.adaptPollingProtocol(definition, endpoint: endpoint)
                        return .openRazer(OpenRazerDevice(definition: adapted, endpoint: endpoint))
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            }
            return unavailable(definition.displayName, definition.category, recognised: true, lastError)
        }

        if let name = ProductLists.keyboards25[pid] {
            guard let endpoint = await pickEndpoint(featureInterfaces, preference, "keyboard-\(tagPid)", probe: KeyboardProtocol25.getFirmware)
            else {
                return unavailable(name, .keyboard, recognised: true, "没有找到 90 字节的 HID 控制接口")
            }
            return .keyboard(Keyboard25Device(productId: pid, name: name, endpoint: endpoint))
        }

        let krakenModel = ProductLists.kraken[pid]
        let krakenInterface = krakenModel.flatMap { _ in
            group.interfaces.first { $0.maxOutputReportSize == KrakenProtocol.reportLength && $0.interfaceNumber == 3 }
                ?? group.interfaces.first { $0.maxOutputReportSize == KrakenProtocol.reportLength }
        }
        let kraken = krakenModel.flatMap { model in
            krakenInterface.map { KrakenDevice(productId: pid, model: model, channel: ReportChannel(interface: $0, tag: "kraken-\(tagPid)")) }
        }

        if let name = ProductLists.headsetAudio[pid] {
            let ordered = featureInterfaces.filter { $0.usagePage == 0xFF14 } + featureInterfaces.filter { $0.usagePage != 0xFF14 }
            if let endpoint = await pickEndpoint(ordered, preference, "audio-\(tagPid)", probe: HeadsetAudioProtocol.getFirmware) {
                return .audio(HeadsetAudioDevice(productId: pid, name: name, endpoint: endpoint), lighting: kraken)
            }
            if kraken == nil {
                return unavailable(name, ProductLists.audioCategory(pid), recognised: true, "没有找到 90 字节的 HID 控制接口")
            }
        }

        if let kraken {
            return .kraken(kraken)
        }
        if let model = krakenModel {
            return unavailable(model.name, .headset, recognised: true, "没有找到 37 字节的输出报告接口")
        }

        if let product = ProductLists.chromaStandard[pid] {
            guard let endpoint = await pickEndpoint(featureInterfaces, preference, "chroma-\(tagPid)", probe: ChromaProtocol.getEffect)
            else {
                return unavailable(product.name, product.category, recognised: true, "没有找到 90 字节的 HID 控制接口")
            }
            return .chroma(ChromaDevice(productId: pid, name: product.name, category: product.category, legacy: false, endpoint: endpoint))
        }

        let name = ProductLists.lampArrayNames[pid] ?? group.interfaces.compactMap(\.productName).first ?? "未知雷蛇设备"
        if let lighting = await lampArray(group, pid: pid, name: name, reuse: nil) {
            return .lampArray(lighting)
        }
        return unavailable(name, nil, recognised: false, "此设备不在支持列表中")
    }

    /// Looks for a HID LampArray on any interface with a feature report large enough to hold
    /// the attributes report. The probe is a single GET_REPORT.
    private static func lampArray(_ group: InterfaceGroup, pid: UInt16, name: String, reuse: ReportChannel?) async -> LampArrayDevice? {
        for item in group.interfaces where item.maxFeatureReportSize >= LampArrayProtocol.attributesLength {
            let channel = reuse?.interface.registryId == item.registryId ? reuse!
                : ReportChannel(interface: item, tag: String(format: "lamparray-%04X", pid))
            if let attributes = await LampArrayDevice.probe(channel) {
                DiagnosticLog.shared.write(String(format: "scan-%04X", pid), "HID LampArray：\(attributes.lampCount) 个灯")
                return LampArrayDevice(productId: pid, name: name, channel: channel, attributes: attributes)
            }
        }
        return nil
    }

    /// Chooses the feature interface that answers a harmless GET; falls back to the first one,
    /// which is what upstream does for the middleware families.
    private static func pickEndpoint(
        _ candidates: [HIDInterface], _ preference: TransportPreference, _ tag: String,
        probe: (UInt8) throws -> RazerReport
    ) async -> FeatureEndpoint? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return FeatureEndpoint(interface: candidates[0], preference: preference, tag: tag)
        }
        for candidate in candidates {
            let endpoint = FeatureEndpoint(interface: candidate, preference: preference, tag: tag)
            if let report = try? probe(endpoint.nextTransactionId()),
               (try? await endpoint.query(report, wait: 0.020, label: "探测接口")) != nil {
                return endpoint
            }
        }
        return FeatureEndpoint(interface: candidates[0], preference: preference, tag: tag)
    }

    /// Interfaces of the demo devices.
    public static func simulatedInterfaces() -> [HIDInterface] {
        SimulatedDevice.demoDevices().enumerated().flatMap { index, device in
            device.interfaces(registryBase: 0xD000_0000 + UInt64(index) * 16)
        }
    }
}
