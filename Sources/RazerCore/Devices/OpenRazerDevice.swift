import Foundation

public enum KeyswitchOptimization: String, CaseIterable, Sendable, Identifiable {
    case typing, gaming

    public var id: String { rawValue }
    public var displayName: String { self == .typing ? "打字（防误触）" : "游戏（最快响应）" }
}

public enum ScrollMode: UInt8, CaseIterable, Sendable, Identifiable {
    case tactile = 0x00, freeSpin = 0x01

    public var id: UInt8 { rawValue }
    public var displayName: String { self == .tactile ? "段落模式" : "无极滚动" }
}

/// Values read from a device; nil means the device did not report the value.
public struct OpenRazerState: Sendable {
    public var firmware: String?
    public var serial: String?
    public var deviceMode: UInt8?
    public var batteryPercent: Int?
    public var charging: Bool?
    public var pollingRate: Int?
    public var dpi: (x: Int, y: Int)?
    public var dpiStages: DpiStages?
    public var idleSeconds: Int?
    public var lowBatteryThreshold: Int?
    public var brightness: [LedZone: UInt8] = [:]
    public var scrollMode: ScrollMode?
    public var scrollAcceleration: Bool?
    public var smartReel: Bool?
    public var keyswitch: KeyswitchOptimization?
    /// Capabilities whose read the firmware refused; the UI hides them.
    public var unsupported: Set<Capability> = []
    public var errors: [String] = []

    public init() {}
}

/// A resolved OpenRazer catalog device on macOS.
public final class OpenRazerDevice: @unchecked Sendable {
    public let definition: DeviceDefinition
    public let endpoint: FeatureEndpoint
    public let capabilities: Set<Capability>
    public let lightingZones: [LedZone: LightingZoneCapabilities]
    private let tag: String

    public init(definition: DeviceDefinition, endpoint: FeatureEndpoint) {
        self.definition = definition
        self.endpoint = endpoint
        capabilities = CapabilityResolver.capabilities(definition)
        lightingZones = CapabilityResolver.lightingZones(definition)
        tag = String(format: "openrazer-%04X", definition.productId)
    }

    public func has(_ capability: Capability) -> Bool { capabilities.contains(capability) }

    @discardableResult
    func execute(_ request: RazerRequest, allowRemainingPacketsMismatch: Bool = false) async throws -> RazerReport {
        do {
            return try await endpoint.query(request.report, wait: definition.deviceWait, label: request.builder,
                                            allowRemainingPacketsMismatch: allowRemainingPacketsMismatch)
        } catch RazerError.rejected(let message) {
            throw RazerError.notSupported(message)
        }
    }

    /// Side-effect-free GETs used to confirm that an interface is this device's control endpoint.
    static func safeProbes(_ definition: DeviceDefinition) -> [RazerRequest] {
        var probes: [RazerRequest] = []
        func add(_ builder: String, _ make: () throws -> RazerRequest) {
            if definition.transactions[builder] != nil, !probes.contains(where: { $0.builder == builder }),
               let request = try? make() {
                probes.append(request)
            }
        }
        add("razer_chroma_standard_get_firmware_version") { try StandardProtocol.getFirmware(definition) }
        add("razer_chroma_standard_get_serial") { try StandardProtocol.getSerial(definition) }
        add("razer_chroma_standard_get_device_mode") { try StandardProtocol.getDeviceMode(definition) }
        add("razer_chroma_misc_get_battery_level") { try MouseProtocol.getBattery(definition) }
        add("razer_chroma_misc_get_dpi_xy") { try MouseProtocol.getDpi(definition) }
        add("razer_chroma_misc_get_dpi_xy_byte") { try MouseProtocol.getDpi(definition) }
        add("razer_chroma_misc_get_polling_rate2") { try MouseProtocol.getPollingRate(definition) }
        add("razer_chroma_misc_get_polling_rate") { try MouseProtocol.getPollingRate(definition) }
        for builder in LightingProtocol.brightnessReadBuilders {
            add(builder) { try LightingProtocol.getBrightness(definition, storage: nil, zone: nil) }
        }
        return probes
    }

    /// Returns true when one safe GET is answered on this endpoint.
    static func probe(_ definition: DeviceDefinition, endpoint: FeatureEndpoint) async throws -> Bool {
        var lastError: Error?
        for request in safeProbes(definition) {
            do {
                _ = try await endpoint.query(request.report, wait: definition.deviceWait, label: "探测 \(request.builder)")
                return true
            } catch let error as RazerError {
                if case .permissionDenied = error { throw error }
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return false
    }

    /// Middleware-admitted 8 kHz mice (e.g. Basilisk V4 Pro) inherit a sibling's legacy polling
    /// command (00:85), which their firmware rejects with 0x05. When that happens, read the
    /// HyperPolling command (00:C0) once; if it answers with a known rate, drive the device with
    /// the polling_rate2 family the catalog uses for every other 8 kHz mouse.
    static func adaptPollingProtocol(_ definition: DeviceDefinition, endpoint: FeatureEndpoint) async -> DeviceDefinition {
        guard let txn = definition.transactions["razer_chroma_misc_get_polling_rate"],
              definition.transactions["razer_chroma_misc_get_polling_rate2"] == nil,
              let legacy = try? MouseProtocol.getPollingRate(definition)
        else { return definition }
        do {
            _ = try await endpoint.query(legacy.report, wait: definition.deviceWait, label: "探测旧式回报率命令")
            return definition
        } catch RazerError.notSupported, RazerError.rejected {
            // Fall through to the HyperPolling probe.
        } catch {
            return definition
        }
        guard let probe = try? RazerReport(transactionId: txn, dataSize: 0x01, commandClass: 0x00, commandId: 0xC0),
              let response = try? await endpoint.query(probe, wait: definition.deviceWait, label: "探测 HyperPolling 回报率命令"),
              (try? MouseProtocol.parsePollingRate(response, highRate: true)) != nil
        else { return definition }
        var transactions = definition.transactions
        transactions.removeValue(forKey: "razer_chroma_misc_get_polling_rate")
        transactions.removeValue(forKey: "razer_chroma_misc_set_polling_rate")
        transactions["razer_chroma_misc_get_polling_rate2"] = txn
        var sequences = definition.commandSequences
        sequences["razer_chroma_misc_set_polling_rate2"] = [
            CommandStep(transactionId: txn, fixedArgument0: 0x00), CommandStep(transactionId: txn, fixedArgument0: 0x01),
        ]
        DiagnosticLog.shared.write(String(format: "openrazer-%04X", definition.productId), "改用 HyperPolling 回报率命令（00:C0 / 00:40）")
        return definition.with(transactions: transactions, commandSequences: sequences)
    }

    // MARK: Reading

    public func readState() async -> OpenRazerState {
        var state = OpenRazerState()
        func read<T>(_ capability: Capability, _ label: String, _ body: () async throws -> T) async -> T? {
            guard has(capability) else { return nil }
            do {
                return try await body()
            } catch let error as RazerError where error.meansUnsupported {
                // A catalog entry can advertise an optional read that this firmware rejects or
                // never answers. Keep the rest of the page usable and hide that control.
                state.unsupported.insert(capability)
                DiagnosticLog.shared.write(tag, "可选读取“\(label)”不可用：\(error.localizedDescription)")
                return nil
            } catch {
                state.errors.append("\(label)：\(error.localizedDescription)")
                return nil
            }
        }

        state.firmware = await read(.firmwareRead, "固件") {
            try StandardProtocol.parseFirmware(try await execute(try StandardProtocol.getFirmware(definition)))
        }
        if has(.serialRead) {
            state.serial = try? StandardProtocol.parseSerial(try await execute(try StandardProtocol.getSerial(definition)))
            if let serial = state.serial, serial.isEmpty || serial.allSatisfy({ $0 == "0" }) {
                state.serial = nil
            }
        }
        if state.serial == nil {
            state.serial = endpoint.interface.serialNumber
        }
        state.batteryPercent = await read(.batteryRead, "电量") {
            try MouseProtocol.parseBatteryPercent(try await execute(try MouseProtocol.getBattery(definition)))
        }
        state.charging = await read(.chargingRead, "充电状态") {
            try MouseProtocol.parseSecondArgument(try await execute(try MouseProtocol.getCharging(definition))) != 0
        }
        state.pollingRate = await read(.pollingRateRead, "回报率") { try await getPollingRate() }
        state.dpi = await read(.dpiRead, "DPI") { try await getDpi() }
        state.dpiStages = await read(.dpiStagesRead, "DPI 档位") {
            try MouseProtocol.parseDpiStages(definition, try await execute(try MouseProtocol.getDpiStages(definition)))
        }
        state.idleSeconds = await read(.idleTimeoutRead, "休眠时间") {
            try MouseProtocol.parseIdleSeconds(try await execute(try MouseProtocol.getIdleTime(definition)))
        }
        state.lowBatteryThreshold = await read(.lowBatteryThresholdRead, "低电量提醒") {
            try MouseProtocol.parseLowBatteryThreshold(try await execute(try MouseProtocol.getLowBatteryThreshold(definition)))
        }
        for zone in lightingZones.values.filter(\.canReadBrightness).map(\.zone).sorted() {
            if let value = await read(.brightnessRead, "\(zone.displayName)亮度", { try await getBrightness(zone: zone) }) {
                state.brightness[zone] = value
            }
        }
        state.scrollMode = await read(.scrollModeRead, "滚轮模式") {
            ScrollMode(rawValue: try MouseProtocol.parseSecondArgument(try await execute(try MouseProtocol.getScrollMode(definition))))
        } ?? nil
        state.scrollAcceleration = await read(.scrollAccelerationRead, "滚轮加速") {
            try MouseProtocol.parseSecondArgument(try await execute(try MouseProtocol.getScrollAcceleration(definition))) != 0
        }
        state.smartReel = await read(.smartReelRead, "智能滚轮") {
            try MouseProtocol.parseSecondArgument(try await execute(try MouseProtocol.getSmartReel(definition))) != 0
        }
        state.keyswitch = await read(.keyswitchOptimizationRead, "按键优化") { try await getKeyswitchOptimization() }
        return state
    }

    /// Battery and charging only, for the periodic refresh.
    public func readBatteryOnly() async throws -> (percent: Int?, charging: Bool?) {
        guard has(.batteryRead) else { return (nil, nil) }
        let percent = try MouseProtocol.parseBatteryPercent(try await execute(try MouseProtocol.getBattery(definition)))
        let charging = has(.chargingRead)
            ? try? MouseProtocol.parseSecondArgument(try await execute(try MouseProtocol.getCharging(definition))) != 0
            : nil
        return (percent, charging)
    }

    public func getPollingRate() async throws -> Int {
        try MouseProtocol.parsePollingRate(try await execute(try MouseProtocol.getPollingRate(definition)),
                                           highRate: MouseProtocol.usesHighPollingRate(definition))
    }

    public func getDpi() async throws -> (x: Int, y: Int) {
        try MouseProtocol.parseDpi(try await execute(try MouseProtocol.getDpi(definition)),
                                   byteEncoding: MouseProtocol.usesByteDpi(definition))
    }

    public func getBrightness(zone: LedZone) async throws -> UInt8 {
        let resolved = try LightingProtocol.resolveBrightnessZone(definition, write: false, zone: zone)
        guard lightingZones[resolved]?.canReadBrightness == true else {
            throw RazerError.notSupported("灯区 \(resolved.displayName) 不支持读取亮度")
        }
        let request = try LightingProtocol.getBrightness(definition, storage: nil, zone: resolved)
        return try LightingProtocol.parseBrightness(request, try await execute(request))
    }

    public func getKeyswitchOptimization() async throws -> KeyswitchOptimization {
        let request = try StandardProtocol.create(definition, "razer_chroma_misc_get_keyswitch_optimization",
                                                  dataSize: 0x04, commandClass: 0x02, commandId: 0x82)
        let args = Array(try (try await execute(request)).successfulArguments(minimumLength: 4))
        switch (args[1], args[3]) {
        case (0x14, 0x28): return .typing
        case (0x00, 0x00): return .gaming
        default: throw RazerError.invalidResponse("未知的按键优化状态")
        }
    }

    public var maximumDpi: Int { MouseProtocol.maximumDpi(definition) }

    /// Polling rates the page may offer.
    public var pollingRateOptions: [Int] {
        if !definition.pollingRates.isEmpty { return definition.pollingRates.sorted() }
        if MouseProtocol.usesHighPollingRate(definition) { return [125, 500, 1000] }
        return [125, 500, 1000]
    }

    // MARK: Writing

    /// Writes the polling rate and reads it back; nil when the device cannot be read back.
    public func setPollingRate(_ hertz: Int) async throws -> Int? {
        for request in try MouseProtocol.setPollingRate(definition, hertz: hertz) {
            try await execute(request)
        }
        guard has(.pollingRateRead) else { return nil }
        return try? await getPollingRate()
    }

    public func setDpi(x: Int, y: Int) async throws -> (x: Int, y: Int)? {
        try await execute(try MouseProtocol.setDpi(definition, x: x, y: y))
        guard has(.dpiRead) else { return nil }
        return try? await getDpi()
    }

    public func setDpiStages(_ stages: DpiStages) async throws {
        try await execute(try MouseProtocol.setDpiStages(definition, stages))
    }

    public func setIdleTime(seconds: Int) async throws {
        try await execute(try MouseProtocol.setIdleTime(definition, seconds: seconds))
    }

    public func setLowBatteryThreshold(percent: Int) async throws {
        try await execute(try MouseProtocol.setLowBatteryThreshold(definition, percent: percent))
    }

    public func setBrightness(_ value: UInt8, zone: LedZone) async throws {
        let resolved = try LightingProtocol.resolveBrightnessZone(definition, write: true, zone: zone)
        guard lightingZones[resolved]?.canWriteBrightness == true else {
            throw RazerError.notSupported("灯区 \(resolved.displayName) 不支持设置亮度")
        }
        try await execute(try LightingProtocol.setBrightness(definition, storage: nil, zone: resolved, brightness: value))
    }

    public func setLighting(_ settings: LightingSettings) async throws {
        // The custom-frame selector has a fixed storage argument, so it only resolves through
        // the device-wide default; createEffect then checks the requested zone against it.
        let zone = try LightingProtocol.resolveEffectZone(
            definition, settings.effect, storage: settings.storage, zone: settings.effect == .custom ? nil : settings.zone)
        guard lightingZones[zone]?.effects.contains(settings.effect) == true else {
            throw RazerError.notSupported("灯区 \(zone.displayName) 不支持\(settings.effect.displayName)")
        }
        for request in try LightingProtocol.createEffectRequests(definition, settings) {
            try await execute(request)
        }
    }

    public var supportsMatrixFrames: Bool { has(.matrixFrameWrite) && definition.matrixDimensions != nil }

    /// Fills the whole key matrix with one color and switches to the custom-frame effect.
    public func setMatrixColor(_ color: RazerColor) async throws {
        guard let matrix = definition.matrixDimensions, supportsMatrixFrames else {
            throw RazerError.notSupported("该设备没有可写的按键矩阵")
        }
        var rows: [RazerReport] = []
        for row in 0..<matrix.rows {
            var start = 0
            while start < Int(matrix.columns) {
                let count = min(25, Int(matrix.columns) - start)
                rows.append(try LightingProtocol.setCustomRow(
                    definition, row: row, startColumn: UInt8(start),
                    colors: Array(repeating: color, count: count)).report)
                start += count
            }
        }
        for report in rows {
            _ = try await endpoint.query(report, wait: definition.deviceWait, label: "矩阵帧")
        }
        if lightingZones.values.contains(where: { $0.effects.contains(.custom) }) {
            try await setLighting(LightingSettings(effect: .custom))
        }
    }

    public func setScrollMode(_ mode: ScrollMode) async throws {
        try await execute(try MouseProtocol.setScrollMode(definition, mode: mode.rawValue))
    }

    public func setScrollAcceleration(_ enabled: Bool) async throws {
        try await execute(try MouseProtocol.setScrollAcceleration(definition, enabled: enabled))
    }

    public func setSmartReel(_ enabled: Bool) async throws {
        try await execute(try MouseProtocol.setSmartReel(definition, enabled: enabled))
    }

    public func setKeyswitchOptimization(_ value: KeyswitchOptimization) async throws {
        let typing = value == .typing
        let command1 = try StandardProtocol.create(
            definition, "razer_chroma_misc_set_keyswitch_optimization_command1", dataSize: 0x04, commandClass: 0x02,
            commandId: 0x02, arguments: typing ? [0x00, 0x14, 0x00, 0x28, 0x00] : [0x00, 0x00, 0x00, 0x00],
            allowArgumentsBeyondDeclaredSize: typing)
        let command2 = try StandardProtocol.create(
            definition, "razer_chroma_misc_set_keyswitch_optimization_command2", dataSize: 0x05, commandClass: 0x02,
            commandId: 0x15, arguments: typing ? [0x01, 0x00, 0x14, 0x00, 0x28, 0x00] : [0x01, 0x00, 0x00, 0x00, 0x00],
            allowArgumentsBeyondDeclaredSize: typing)
        try await execute(command1)
        try await execute(command2)
    }

    public func setHyperPollingIndicator(mode: UInt8) async throws {
        guard (1...3).contains(mode) else { throw RazerError.invalidArgument("指示灯模式需为 1 到 3") }
        try await execute(try StandardProtocol.create(
            definition, "razer_chroma_misc_set_hyperpolling_wireless_dongle_indicator_led_mode",
            dataSize: 0x01, commandClass: 0x07, commandId: 0x10, arguments: [mode]))
    }

    public func pairHyperPolling(mouseProductId: UInt16) async throws {
        try await execute(try StandardProtocol.create(
            definition, "razer_chroma_misc_set_hyperpolling_wireless_dongle_pair_step1",
            dataSize: 0x01, commandClass: 0x00, commandId: 0x46, arguments: [0x01]))
        try await execute(try StandardProtocol.create(
            definition, "razer_chroma_misc_set_hyperpolling_wireless_dongle_pair_step2",
            dataSize: 0x03, commandClass: 0x00, commandId: 0x41, arguments: [0x01, mouseProductId.high, mouseProductId.low]))
    }

    public func unpairHyperPolling(mouseProductId: UInt16) async throws {
        try await execute(try StandardProtocol.create(
            definition, "razer_chroma_misc_set_hyperpolling_wireless_dongle_unpair",
            dataSize: 0x02, commandClass: 0x00, commandId: 0x42, arguments: [mouseProductId.high, mouseProductId.low]))
    }

    // MARK: Onboard button mapping

    /// Mice may answer the middleware's button-assignment commands; whether they do is only
    /// known after the button-list GET, which has no side effects.
    public var mayHaveButtonMapping: Bool { definition.category == .mouse }

    /// Button ids the firmware lists, or an empty list when the device refuses the command.
    public func mappableButtons() async throws -> [UInt8] {
        guard mayHaveButtonMapping else { return [] }
        do {
            return try MappingProtocol.parseButtonList(try await execute(try MappingProtocol.getButtonList()))
        } catch let error as RazerError where error.meansUnsupported {
            DiagnosticLog.shared.write(tag, "设备不支持板载按键映射：\(error.localizedDescription)")
            return []
        }
    }

    public func buttonAssignment(_ button: UInt8, layer: MappingLayer) async throws -> ButtonAssignment {
        try MappingProtocol.parseAssignment(try await execute(try MappingProtocol.getAssignment(button: button, layer: layer)))
    }

    /// Writes an assignment, reads it back and restores the previous one if the device kept
    /// something else.
    public func setButtonAssignment(_ button: UInt8, layer: MappingLayer, _ assignment: ButtonAssignment) async throws {
        let previous = try await buttonAssignment(button, layer: layer)
        if previous == assignment { return }
        do {
            try await execute(try MappingProtocol.setAssignment(button: button, layer: layer, assignment))
            let actual = try await buttonAssignment(button, layer: layer)
            guard actual == assignment else {
                throw RazerError.invalidResponse("设备保存的是 \(MappingActions.describe(actual))")
            }
        } catch {
            _ = try? await execute(try MappingProtocol.setAssignment(button: button, layer: layer, previous))
            throw error
        }
    }

    /// Restores driver mode on wireless mice that a previous host left in normal mode, which
    /// keeps them off the 2.4 GHz link. Only modes 0x00 are rewritten.
    public func ensureDriverMode() async throws -> Bool {
        guard has(.deviceModeWrite) else { return false }
        let before = try StandardProtocol.parseDeviceMode(try await execute(try StandardProtocol.getDeviceMode(definition)))
        guard before == StandardProtocol.normalDeviceMode else {
            return before == StandardProtocol.driverDeviceMode
        }
        try await execute(try StandardProtocol.setDriverDeviceMode(definition))
        let after = try StandardProtocol.parseDeviceMode(try await execute(try StandardProtocol.getDeviceMode(definition)))
        return after == StandardProtocol.driverDeviceMode
    }
}
