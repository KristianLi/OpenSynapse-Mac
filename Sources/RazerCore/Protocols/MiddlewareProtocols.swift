import Foundation

// Protocol 25 commands from the Synapse middleware bundles. They use the same 90-byte
// envelope as OpenRazer, with a transaction id that cycles 0...0x1F per request.

/// Huntsman V3 / Pro Type family keyboards.
enum KeyboardProtocol25 {
    static let pollingRates: [(code: UInt8, hertz: Int)] = [
        (0x01, 8000), (0x02, 4000), (0x04, 2000), (0x08, 1000), (0x10, 500), (0x20, 250), (0x40, 125),
    ]

    static func getFirmware(_ txn: UInt8) throws -> RazerReport { try create(txn, 4, 0x00, 0x87) }
    static func getSerial(_ txn: UInt8) throws -> RazerReport { try create(txn, 22, 0x00, 0x82) }
    /// The Pro Type family answers the serial on the class 1 command instead.
    static func getSerialAlt(_ txn: UInt8) throws -> RazerReport { try create(txn, 0, 0x01, 0x83) }
    static func getGameMode(_ txn: UInt8) throws -> RazerReport { try create(txn, 4, 0x00, 0x88) }
    static func setGameMode(_ txn: UInt8, gameMode: UInt8, keyCover: UInt8, lifted: UInt8) throws -> RazerReport {
        try create(txn, 4, 0x00, 0x08, [gameMode, keyCover, lifted])
    }
    static func getPollingRate(_ txn: UInt8) throws -> RazerReport { try create(txn, 2, 0x00, 0x8E) }
    static func setPollingRate(_ txn: UInt8, code: UInt8) throws -> RazerReport { try create(txn, 2, 0x00, 0x0E, [code]) }
    static func getBattery(_ txn: UInt8) throws -> RazerReport { try create(txn, 2, 0x07, 0x80) }
    static func getCharging(_ txn: UInt8) throws -> RazerReport { try create(txn, 2, 0x07, 0x84) }

    static func readFirmware(_ response: RazerReport) throws -> String {
        let data = try args(response, 2)
        return "\(data[0]).\(data[1])"
    }

    static func readSerial(_ response: RazerReport) throws -> String {
        let data = try args(response, 1)
        let end = data.firstIndex { $0 == 0 || $0 < 0x20 || $0 >= 0x7F } ?? data.count
        return String(decoding: data[..<end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    static func readGameMode(_ response: RazerReport) throws -> (gameMode: UInt8, keyCover: UInt8, lifted: UInt8) {
        let data = try args(response, 3)
        return (data[0], data[1], data[2])
    }

    static func readPollingRate(_ response: RazerReport) throws -> Int? {
        let code = try args(response, 2)[1]
        return pollingRates.first { $0.code == code }?.hertz
    }

    static func readBatteryPercent(_ response: RazerReport) throws -> Int { Int(try args(response, 1)[0]) * 100 / 255 }
    static func readCharging(_ response: RazerReport) throws -> Bool { try args(response, 1)[0] != 0 }

    static func pollingCode(_ hertz: Int) -> UInt8? { pollingRates.first { $0.hertz == hertz }?.code }

    static func create(_ txn: UInt8, _ size: UInt8, _ commandClass: UInt8, _ command: UInt8, _ arguments: [UInt8] = []) throws -> RazerReport {
        try RazerReport(transactionId: txn, dataSize: size, commandClass: commandClass, commandId: command, arguments: arguments,
                        allowArgumentsBeyondDeclaredSize: true)
    }

    /// Middleware parsers read the whole argument area without trusting the declared size.
    static func args(_ response: RazerReport, _ length: Int) throws -> [UInt8] {
        let data = Array(response.rawArguments)
        guard RazerReport.isAcceptedStatus(response.status), data.count >= length else {
            throw RazerError.invalidResponse("响应缺少数据")
        }
        return data
    }
}

public enum ChromaEffect: UInt8, CaseIterable, Sendable, Identifiable {
    case off = 0, `static` = 1, breathing = 2, spectrum = 3, audioMeter = 4

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .off: "关闭"
        case .static: "静态"
        case .breathing: "呼吸"
        case .spectrum: "光谱循环"
        case .audioMeter: "音频律动"
        }
    }

    public var colorCount: Int {
        switch self {
        case .static: 1
        case .breathing: 2
        default: 0
        }
    }
}

/// Class 0x10 Chroma commands (lamps, docks, ARGB controllers, newer mice and keyboards) and
/// the older class 0x0F variant some keyboards use, which has no brightness command.
enum ChromaProtocol {
    static let maxColors = 2

    static func getEffect(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 0, 0x10, 0x83) }

    static func setEffect(_ txn: UInt8, _ effect: ChromaEffect, colors: [RazerColor], flags: UInt8 = 0, rate: UInt8 = 0) throws -> RazerReport {
        let palette = Array(colors.prefix(maxColors))
        let arguments = [effect.rawValue, flags, rate, UInt8(palette.count)] + palette.flatMap(\.bytes)
        return try KeyboardProtocol25.create(txn, UInt8(arguments.count), 0x10, 0x03, arguments)
    }

    static func getBrightness(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 0, 0x10, 0x85) }
    static func setBrightness(_ txn: UInt8, level: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 1, 0x10, 0x05, [level]) }

    static func readEffect(_ response: RazerReport) throws -> (effect: ChromaEffect?, colors: [RazerColor]) {
        let data = try KeyboardProtocol25.args(response, 4)
        let count = Int(data[3])
        guard count <= maxColors, data.count >= 4 + count * 3 else {
            throw RazerError.invalidResponse("灯效声明了 \(count) 个颜色")
        }
        return (ChromaEffect(rawValue: data[0]), colors(data, offset: 4, count: count))
    }

    static func readBrightnessPercent(_ response: RazerReport) throws -> Int {
        Int((Double(try KeyboardProtocol25.args(response, 1)[0]) * 100 / 255).rounded(.up))
    }

    static func brightnessLevel(percent: Int) -> UInt8 {
        UInt8((Double(min(max(percent, 0), 100)) * 255 / 100).rounded())
    }

    static func getLegacyEffect(_ txn: UInt8) throws -> RazerReport {
        try KeyboardProtocol25.create(txn, 80, 0x0F, 0x82, [1, 0])
    }

    static func setLegacyEffect(_ txn: UInt8, _ effect: ChromaEffect, colors: [RazerColor]) throws -> RazerReport {
        guard effect != .audioMeter else {
            throw RazerError.notSupported("0x0F 类灯光只有四种效果")
        }
        let palette = Array(colors.prefix(maxColors))
        let arguments = [1, 0, effect.rawValue, 0, 0, UInt8(palette.count)] + palette.flatMap(\.bytes)
        return try KeyboardProtocol25.create(txn, UInt8(arguments.count), 0x0F, 0x02, arguments)
    }

    static func readLegacyEffect(_ response: RazerReport) throws -> (effect: ChromaEffect?, colors: [RazerColor]) {
        let data = try KeyboardProtocol25.args(response, 6)
        let count = Int(data[5])
        guard count <= maxColors, data.count >= 6 + count * 3 else {
            throw RazerError.invalidResponse("灯效声明了 \(count) 个颜色")
        }
        // Class 0x0F uses id 4 for Wave, not AudioMeter, so anything above Spectrum is unknown.
        return (data[2] <= ChromaEffect.spectrum.rawValue ? ChromaEffect(rawValue: data[2]) : nil,
                colors(data, offset: 6, count: count))
    }

    private static func colors(_ data: [UInt8], offset: Int, count: Int) -> [RazerColor] {
        (0..<count).map { RazerColor(data[offset + $0 * 3], data[offset + $0 * 3 + 1], data[offset + $0 * 3 + 2]) }
    }
}

public enum AudioSource: UInt8, CaseIterable, Sendable, Identifiable {
    case none = 0, spdif = 1, aux = 2, bluetooth = 3, usb = 4

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .none: "无"
        case .spdif: "光纤 S/PDIF"
        case .aux: "AUX"
        case .bluetooth: "蓝牙"
        case .usb: "USB"
        }
    }
}

public enum AncState: UInt8, CaseIterable, Sendable, Identifiable {
    case off = 0, on = 1, ambient = 80

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .off: "关闭"
        case .on: "主动降噪"
        case .ambient: "环境音"
        }
    }
}

/// Protocol 25 audio commands: EQ, bass, microphone, audio source, ANC, noise suppression.
enum HeadsetAudioProtocol {
    static let tenBandFrequencies = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let presets: [(value: UInt8, name: String)] = [
        (0x00, "默认"), (0x01, "游戏"), (0x02, "音乐"), (0x03, "电影"), (0x04, "高音增强"),
        (0x05, "麦克风增强"), (0x06, "播客"), (0x10, "自定义"),
    ]

    static func getFirmware(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x00, 0x81) }
    static func getBattery(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x07, 0x80) }
    static func getCharging(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x07, 0x84) }
    static func getEqPreset(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x82, [0]) }
    static func setEqPreset(_ txn: UInt8, _ preset: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x02, [0, preset]) }
    static func getEqBands(_ txn: UInt8, tenBand: Bool) throws -> RazerReport {
        try KeyboardProtocol25.create(txn, tenBand ? 11 : 9, 0x08, 0x84, [0])
    }
    static func setEqBands(_ txn: UInt8, _ bands: [UInt8]) throws -> RazerReport {
        guard bands.count == 10 || bands.count == 8 else {
            throw RazerError.invalidArgument("均衡器需要 10 段或 8 段")
        }
        return try KeyboardProtocol25.create(txn, UInt8(bands.count + 1), 0x08, 0x04, [0] + bands)
    }
    static func getBass(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x87, [0]) }
    static func setBass(_ txn: UInt8, _ level: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x07, [0, level]) }
    static func getMicMute(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x88, [0]) }
    static func setMicMute(_ txn: UInt8, _ mute: Bool) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x08, [0, mute ? 1 : 0]) }
    static func getMicVolume(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x97, [0]) }
    static func setMicVolume(_ txn: UInt8, _ volume: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x17, [0, volume]) }
    static func getAudioSource(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x8A, [0]) }
    static func setAudioSource(_ txn: UInt8, _ source: AudioSource) throws -> RazerReport {
        try KeyboardProtocol25.create(txn, 2, 0x08, 0x0A, [0, source.rawValue])
    }
    static func getNoiseSuppression(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 2, 0x08, 0x9C, [0]) }
    static func setNoiseSuppression(_ txn: UInt8, _ enabled: Bool) throws -> RazerReport {
        try KeyboardProtocol25.create(txn, 2, 0x08, 0x1C, [0, enabled ? 1 : 0])
    }
    /// The middleware declares one argument byte but the firmware answers profile, state and level.
    static func getAnc(_ txn: UInt8) throws -> RazerReport { try KeyboardProtocol25.create(txn, 1, 0x18, 0x86, [0]) }
    static func setAnc(_ txn: UInt8, _ state: AncState, level: UInt8) throws -> RazerReport {
        try KeyboardProtocol25.create(txn, 3, 0x18, 0x06, [0, state.rawValue, level])
    }

    static func readSecond(_ response: RazerReport) throws -> UInt8 { try KeyboardProtocol25.args(response, 2)[1] }

    static func readEqBands(_ response: RazerReport, tenBand: Bool) throws -> [UInt8] {
        let count = tenBand ? 10 : 8
        return Array(try KeyboardProtocol25.args(response, count + 1)[1...count])
    }

    static func readAnc(_ response: RazerReport) throws -> (state: AncState?, level: UInt8) {
        let data = try KeyboardProtocol25.args(response, 3)
        return (AncState(rawValue: data[1]), data[2])
    }
}

/// Kraken headsets: 37-byte output report 0x04 that writes into the headset's memory map.
public enum KrakenLayout: Sendable { case rainie, kylie }

enum KrakenProtocol {
    static let reportLength = 37
    static let reportId: UInt8 = 0x04

    private static let rainieEffect: UInt16 = 0x1008
    private static let rainieBreathing: UInt16 = 0x15DE
    private static let customAddress: UInt16 = 0x1189
    private static let kylieEffect: UInt16 = 0x172D
    private static let kylieBreathing: [UInt16] = [0x1741, 0x1745, 0x174D]

    static func request(address: UInt16, _ arguments: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = reportId
        report[1] = 0x40
        report[2] = UInt8(arguments.count)
        report[3] = address.high
        report[4] = address.low
        report.replaceSubrange(5..<(5 + arguments.count), with: arguments)
        return report
    }

    static func effectAddress(_ layout: KrakenLayout) -> UInt16 { layout == .rainie ? rainieEffect : kylieEffect }

    static func off(_ layout: KrakenLayout) -> [[UInt8]] { [request(address: effectAddress(layout), [0x00])] }

    static func staticColor(_ layout: KrakenLayout, _ color: RazerColor, writeColor: Bool) -> [[UInt8]] {
        var reports: [[UInt8]] = []
        if writeColor {
            reports.append(request(address: layout == .rainie ? rainieBreathing : kylieBreathing[0], color.bytes))
        }
        reports.append(request(address: effectAddress(layout), [0x01]))
        return reports
    }

    static func custom(_ layout: KrakenLayout, _ color: RazerColor) -> [[UInt8]] {
        [request(address: customAddress, color.bytes), request(address: effectAddress(layout), [0x01])]
    }

    static func spectrum(_ layout: KrakenLayout) -> [[UInt8]] { [request(address: effectAddress(layout), [0x05])] }

    static func breathing(_ layout: KrakenLayout, _ colors: [RazerColor]) throws -> [[UInt8]] {
        guard (1...3).contains(colors.count) else {
            throw RazerError.invalidArgument("Kraken 呼吸需要 1 到 3 种颜色")
        }
        guard layout == .kylie || colors.count == 1 else {
            throw RazerError.notSupported("该 Kraken 型号只支持单色呼吸")
        }
        let base = layout == .rainie ? rainieBreathing : kylieBreathing[colors.count - 1]
        var reports = colors.enumerated().map { request(address: base + UInt16($0.offset * 4), $0.element.bytes) }
        reports.append(request(address: effectAddress(layout), [[0x0B, 0x19, 0x29][colors.count - 1]]))
        return reports
    }
}

public enum BlackSharkAncMode: UInt8, CaseIterable, Sendable, Identifiable {
    case off = 0x00, anc = 0x01, ambient = 0x50

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .off: "关闭"
        case .anc: "主动降噪"
        case .ambient: "环境音"
        }
    }
}

/// BlackShark V3 Pro: 64-byte output report 0x02. Byte 9 carries the link (0x80 wireless,
/// 0x00 wired), byte 10 the class, byte 12 the command and byte 62 the XOR CRC of 0..61.
enum BlackSharkProtocol {
    static let reportLength = 64
    static let reportId: UInt8 = 0x02
    static let transactionId: UInt8 = 0x60

    static let batteryClass: UInt8 = 0x21
    static let chargingClass: UInt8 = 0x2A
    static let sidetoneRead: UInt8 = 0x19
    static let sidetoneSet: UInt8 = 0x99
    static let thxClass: UInt8 = 0x9E
    static let ancRead: UInt8 = 0x12
    static let ancSet: UInt8 = 0x92
    static let gameChatRead: UInt8 = 0x5C
    static let gameChatSet: UInt8 = 0xDC

    static func create(_ commandClass: UInt8, _ command: UInt8, direction: UInt8, _ arguments: [UInt8] = []) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = reportId
        report[2] = transactionId
        report[6] = UInt8(4 + arguments.count)
        report[9] = direction
        report[10] = commandClass
        report[12] = command
        report.replaceSubrange(13..<(13 + arguments.count), with: arguments)
        report[62] = crc(report)
        return report
    }

    static func create(_ commandClass: UInt8, _ command: UInt8, wireless: Bool, _ arguments: [UInt8] = []) -> [UInt8] {
        create(commandClass, command, direction: wireless ? 0x80 : 0x00, arguments)
    }

    /// Wake sequence observed in Synapse before the first query on the 2.4 GHz link.
    static let wakeSequence: [[UInt8]] = [
        create(0x02, 0x00, direction: 0x00),
        create(0x2A, 0x00, direction: 0x00),
        create(0x2A, 0x00, direction: 0x80),
    ]

    static func crc(_ report: [UInt8]) -> UInt8 {
        report[0..<62].reduce(0, ^)
    }

    struct Response {
        let status: UInt8
        let commandClass: UInt8
        let subtype: UInt8
        let arguments: [UInt8]
    }

    static func parse(_ report: [UInt8]) -> Response? {
        guard report.count >= reportLength, report[0] == reportId, report[62] == crc(report) else { return nil }
        let count = Int(report[12])
        guard count <= reportLength - 13 else { return nil }
        return Response(status: report[1], commandClass: report[10], subtype: report[11], arguments: Array(report[13..<(13 + count)]))
    }
}
