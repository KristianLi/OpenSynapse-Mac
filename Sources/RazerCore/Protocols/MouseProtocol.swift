import Foundation

public struct DpiStage: Equatable, Sendable, Identifiable {
    public var number: UInt8
    public var x: Int
    public var y: Int

    public var id: UInt8 { number }

    public init(number: UInt8, x: Int, y: Int) {
        self.number = number
        self.x = x
        self.y = y
    }
}

public struct DpiStages: Equatable, Sendable {
    public var activeStage: UInt8
    public var stages: [DpiStage]

    public init(activeStage: UInt8, stages: [DpiStage]) {
        self.activeStage = activeStage
        self.stages = stages
    }
}

/// `razer_chroma_misc_*` builders: battery, polling, DPI, idle, scroll and power settings.
enum MouseProtocol {
    static let highPollingCodes: [(code: UInt8, hertz: Int)] = [
        (0x01, 8000), (0x02, 4000), (0x04, 2000), (0x08, 1000), (0x10, 500), (0x20, 250), (0x40, 125),
    ]
    static let legacyPollingCodes: [(code: UInt8, hertz: Int)] = [(0x01, 1000), (0x02, 500), (0x08, 125)]

    static func getBattery(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_battery_level", dataSize: 0x02, commandClass: 0x07, commandId: 0x80)
    }

    static func getCharging(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_charging_status", dataSize: 0x02, commandClass: 0x07, commandId: 0x84)
    }

    static func usesHighPollingRate(_ device: DeviceDefinition) -> Bool {
        device.transactions["razer_chroma_misc_get_polling_rate2"] != nil
    }

    static func getPollingRate(_ device: DeviceDefinition) throws -> RazerRequest {
        if usesHighPollingRate(device) {
            return try StandardProtocol.create(device, "razer_chroma_misc_get_polling_rate2", dataSize: 0x01, commandClass: 0x00, commandId: 0xC0)
        }
        return try StandardProtocol.create(device, "razer_chroma_misc_get_polling_rate", dataSize: 0x01, commandClass: 0x00, commandId: 0x85)
    }

    static func setPollingRate(_ device: DeviceDefinition, hertz: Int) throws -> [RazerRequest] {
        if !device.pollingRates.isEmpty, !device.pollingRates.contains(hertz) {
            throw RazerError.invalidArgument("该设备未声明 \(hertz) Hz 回报率")
        }
        if let sequence = device.commandSequences["razer_chroma_misc_set_polling_rate2"] {
            let code = try encodeHighPollingRate(hertz)
            return try sequence.map { step in
                RazerRequest(
                    builder: "razer_chroma_misc_set_polling_rate2",
                    report: try RazerReport(transactionId: step.transactionId, dataSize: 0x02, commandClass: 0x00,
                                            commandId: 0x40, arguments: [step.fixedArgument0, code]))
            }
        }
        if device.transactions["razer_chroma_misc_set_polling_rate2"] != nil {
            return [try StandardProtocol.create(device, "razer_chroma_misc_set_polling_rate2", dataSize: 0x02, commandClass: 0x00,
                                                commandId: 0x40, arguments: [0x00, try encodeHighPollingRate(hertz)])]
        }
        return [try StandardProtocol.create(device, "razer_chroma_misc_set_polling_rate", dataSize: 0x01, commandClass: 0x00,
                                            commandId: 0x05, arguments: [try encodeLegacyPollingRate(hertz)])]
    }

    /// OpenRazer sends get_polling_rate2 with data size 1 but the firmware answers in the second
    /// argument byte while still declaring one byte, so the high-rate path reads the raw area.
    static func parsePollingRate(_ response: RazerReport, highRate: Bool) throws -> Int {
        if !highRate {
            let code = try response.successfulArguments(minimumLength: 1).first!
            guard let hertz = legacyPollingCodes.first(where: { $0.code == code })?.hertz else {
                throw RazerError.invalidResponse(String(format: "未知回报率代码 0x%02X", code))
            }
            return hertz
        }
        let raw = Array(try response.successfulRawArguments())[1]
        guard let hertz = highPollingCodes.first(where: { $0.code == raw })?.hertz else {
            throw RazerError.invalidResponse(String(format: "未知高回报率代码 0x%02X", raw))
        }
        return hertz
    }

    static func usesByteDpi(_ device: DeviceDefinition) -> Bool {
        device.transactions["razer_chroma_misc_get_dpi_xy_byte"] != nil
    }

    static func getDpi(_ device: DeviceDefinition) throws -> RazerRequest {
        if usesByteDpi(device) {
            return try StandardProtocol.create(device, "razer_chroma_misc_get_dpi_xy_byte", dataSize: 0x03, commandClass: 0x04, commandId: 0x81)
        }
        let storage = try device.requiredFixedArgument("razer_chroma_misc_get_dpi_xy", index: 0)
        return try StandardProtocol.create(device, "razer_chroma_misc_get_dpi_xy", dataSize: 0x07, commandClass: 0x04,
                                           commandId: 0x85, arguments: [storage])
    }

    static func setDpi(_ device: DeviceDefinition, x: Int, y: Int) throws -> RazerRequest {
        try validateDpi(device, x)
        try validateDpi(device, y)
        if device.transactions["razer_chroma_misc_set_dpi_xy_byte"] != nil {
            return try StandardProtocol.create(device, "razer_chroma_misc_set_dpi_xy_byte", dataSize: 0x03, commandClass: 0x04,
                                               commandId: 0x01, arguments: [try encodeLegacyDpi(x), try encodeLegacyDpi(y), 0x00])
        }
        let storage: UInt8 = device.quirk == .viperProduct184 ? 0x00 : StandardProtocol.variableStore
        return try StandardProtocol.create(device, "razer_chroma_misc_set_dpi_xy", dataSize: 0x07, commandClass: 0x04, commandId: 0x05,
                                           arguments: [storage, x.highByte, x.lowByte, y.highByte, y.lowByte, 0x00, 0x00])
    }

    static func parseDpi(_ response: RazerReport, byteEncoding: Bool) throws -> (x: Int, y: Int) {
        let args = Array(try response.successfulArguments(minimumLength: byteEncoding ? 2 : 5))
        if byteEncoding {
            return (decodeLegacyDpi(args[0]), decodeLegacyDpi(args[1]))
        }
        return ((Int(args[1]) << 8) | Int(args[2]), (Int(args[3]) << 8) | Int(args[4]))
    }

    static func getDpiStages(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_dpi_stages", dataSize: 0x26, commandClass: 0x04,
                                    commandId: 0x86, arguments: [StandardProtocol.variableStore])
    }

    static func setDpiStages(_ device: DeviceDefinition, _ state: DpiStages) throws -> RazerRequest {
        guard (1...5).contains(state.stages.count), state.activeStage >= 1, Int(state.activeStage) <= state.stages.count else {
            throw RazerError.invalidArgument("DPI 档位数量需为 1 到 5，且当前档位必须在范围内")
        }
        var arguments = [UInt8](repeating: 0, count: 3 + state.stages.count * 7)
        arguments[0] = StandardProtocol.variableStore
        arguments[1] = state.activeStage
        arguments[2] = UInt8(state.stages.count)
        for (index, stage) in state.stages.enumerated() {
            guard Int(stage.number) == index + 1 else {
                throw RazerError.invalidArgument("DPI 档位编号必须从 1 开始连续")
            }
            try validateDpi(device, stage.x)
            try validateDpi(device, stage.y)
            let offset = 3 + index * 7
            arguments[offset] = UInt8(index)
            arguments[offset + 1] = stage.x.highByte
            arguments[offset + 2] = stage.x.lowByte
            arguments[offset + 3] = stage.y.highByte
            arguments[offset + 4] = stage.y.lowByte
        }
        let dataSize: UInt8 = device.quirk == .viperProduct184 ? UInt8(arguments.count) : 0x26
        return try StandardProtocol.create(device, "razer_chroma_misc_set_dpi_stages", dataSize: dataSize, commandClass: 0x04,
                                           commandId: 0x06, arguments: arguments)
    }

    static func parseDpiStages(_ device: DeviceDefinition, _ response: RazerReport) throws -> DpiStages {
        let args = Array(try response.successfulArguments(minimumLength: 10))
        let active = args[1]
        let count = Int(args[2])
        guard (1...5).contains(count), active >= 1, Int(active) <= count, args.count >= 3 + count * 7 else {
            throw RazerError.invalidResponse("设备返回的 DPI 档位表头无效")
        }
        var stages: [DpiStage] = []
        for index in 0..<count {
            let offset = 3 + index * 7
            let x = (Int(args[offset + 1]) << 8) | Int(args[offset + 2])
            let y = (Int(args[offset + 3]) << 8) | Int(args[offset + 4])
            stages.append(DpiStage(number: UInt8(index + 1), x: x, y: y))
        }
        return DpiStages(activeStage: active, stages: stages)
    }

    static func getIdleTime(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_idle_time", dataSize: 0x02, commandClass: 0x07, commandId: 0x83)
    }

    static func setIdleTime(_ device: DeviceDefinition, seconds: Int) throws -> RazerRequest {
        guard (60...900).contains(seconds) else {
            throw RazerError.invalidArgument("休眠时间需在 60 到 900 秒之间")
        }
        return try StandardProtocol.create(device, "razer_chroma_misc_set_idle_time", dataSize: 0x02, commandClass: 0x07,
                                           commandId: 0x03, arguments: [seconds.highByte, seconds.lowByte])
    }

    static func parseIdleSeconds(_ response: RazerReport) throws -> Int {
        let args = Array(try response.successfulArguments(minimumLength: 2))
        return (Int(args[0]) << 8) | Int(args[1])
    }

    static func getLowBatteryThreshold(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_low_battery_threshold", dataSize: 0x01, commandClass: 0x07, commandId: 0x81)
    }

    static func setLowBatteryThreshold(_ device: DeviceDefinition, percent: Int) throws -> RazerRequest {
        guard (5...25).contains(percent), percent % 5 == 0 else {
            throw RazerError.invalidArgument("低电量提醒需为 5% 到 25%，步进 5%")
        }
        return try StandardProtocol.create(device, "razer_chroma_misc_set_low_battery_threshold", dataSize: 0x01, commandClass: 0x07,
                                           commandId: 0x01, arguments: [UInt8(percent * 255 / 100)])
    }

    static func parseLowBatteryThreshold(_ response: RazerReport) throws -> Int {
        Int((Double(try response.successfulArguments(minimumLength: 1).first!) * 100 / 255).rounded())
    }

    static func parseBatteryPercent(_ response: RazerReport) throws -> Int {
        let args = Array(try response.successfulArguments(minimumLength: 2))
        return Int((Double(args[1]) * 100 / 255).rounded())
    }

    static func parseSecondArgument(_ response: RazerReport) throws -> UInt8 {
        Array(try response.successfulArguments(minimumLength: 2))[1]
    }

    static func getScrollMode(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_scroll_mode", dataSize: 0x02, commandClass: 0x02, commandId: 0x94,
                                    arguments: [StandardProtocol.variableStore])
    }

    static func setScrollMode(_ device: DeviceDefinition, mode: UInt8) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_set_scroll_mode", dataSize: 0x02, commandClass: 0x02, commandId: 0x14,
                                    arguments: [StandardProtocol.variableStore, mode])
    }

    static func getScrollAcceleration(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_scroll_acceleration", dataSize: 0x02, commandClass: 0x02,
                                    commandId: 0x96, arguments: [StandardProtocol.variableStore])
    }

    static func setScrollAcceleration(_ device: DeviceDefinition, enabled: Bool) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_set_scroll_acceleration", dataSize: 0x02, commandClass: 0x02,
                                    commandId: 0x16, arguments: [StandardProtocol.variableStore, enabled ? 1 : 0])
    }

    static func getSmartReel(_ device: DeviceDefinition) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_get_scroll_smart_reel", dataSize: 0x02, commandClass: 0x02,
                                    commandId: 0x97, arguments: [StandardProtocol.variableStore])
    }

    static func setSmartReel(_ device: DeviceDefinition, enabled: Bool) throws -> RazerRequest {
        try StandardProtocol.create(device, "razer_chroma_misc_set_scroll_smart_reel", dataSize: 0x02, commandClass: 0x02,
                                    commandId: 0x17, arguments: [StandardProtocol.variableStore, enabled ? 1 : 0])
    }

    private static func encodeLegacyPollingRate(_ hertz: Int) throws -> UInt8 {
        guard let code = legacyPollingCodes.first(where: { $0.hertz == hertz })?.code else {
            throw RazerError.invalidArgument("不支持的回报率 \(hertz) Hz")
        }
        return code
    }

    private static func encodeHighPollingRate(_ hertz: Int) throws -> UInt8 {
        guard let code = highPollingCodes.first(where: { $0.hertz == hertz })?.code else {
            throw RazerError.invalidArgument("不支持的回报率 \(hertz) Hz")
        }
        return code
    }

    // Upstream rounds to two decimals and then truncates (C# `(byte)(int)Math.Round(x, 2)`).
    private static func encodeLegacyDpi(_ dpi: Int) throws -> UInt8 {
        let value = (Double(dpi) / 6750 * 255 * 100).rounded() / 100
        guard value >= 0, value < 256 else {
            throw RazerError.invalidArgument("DPI 超出旧式编码范围")
        }
        return UInt8(value.rounded(.towardZero))
    }

    private static func decodeLegacyDpi(_ value: UInt8) -> Int {
        Int(((Double(value) / 255 * 6750 * 100).rounded() / 100).rounded(.towardZero))
    }

    static func maximumDpi(_ device: DeviceDefinition) -> Int { device.maximumDpi ?? 45_000 }

    private static func validateDpi(_ device: DeviceDefinition, _ value: Int) throws {
        let maximum = maximumDpi(device)
        guard value >= 100, value <= maximum else {
            throw RazerError.invalidArgument("DPI 需在 100 到 \(maximum) 之间")
        }
    }
}
