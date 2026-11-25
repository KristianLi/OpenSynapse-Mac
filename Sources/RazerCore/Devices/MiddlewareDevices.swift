import Foundation

/// Shared request plumbing for the protocol 25 families: cycling transaction id, 20 ms wait,
/// and the read → write → read-back → restore-on-failure pattern OpenSynapse uses for writes.
public class Protocol25Device: @unchecked Sendable {
    public let productId: UInt16
    public let name: String
    public let endpoint: FeatureEndpoint
    let wait: TimeInterval = 0.020
    let tag: String

    init(productId: UInt16, name: String, endpoint: FeatureEndpoint, tag: String) {
        self.productId = productId
        self.name = name
        self.endpoint = endpoint
        self.tag = tag
    }

    func query(_ label: String, _ make: (UInt8) throws -> RazerReport) async throws -> RazerReport {
        let report = try make(endpoint.nextTransactionId())
        do {
            return try await endpoint.query(report, wait: wait, label: label)
        } catch RazerError.rejected(let message) {
            throw RazerError.notSupported(message)
        }
    }

    /// Reads a value, collecting the failure text instead of throwing.
    func probe<T>(_ label: String, _ errors: inout [String], _ make: (UInt8) throws -> RazerReport,
                  _ parse: (RazerReport) throws -> T) async -> T? {
        do {
            return try parse(try await query(L("读取\(label)", "Read \(label)"), make))
        } catch {
            errors.append(L("\(label)：\(error.localizedDescription)", "\(label): \(error.localizedDescription)"))
            return nil
        }
    }

    func verifiedWrite<T: Equatable>(
        _ label: String,
        read: @escaping (UInt8) throws -> RazerReport,
        parse: @escaping (RazerReport) throws -> T,
        write: @escaping (T, UInt8) throws -> RazerReport,
        value: T,
        accept: ((T) -> Bool)? = nil
    ) async throws {
        let previous = try parse(try await query(L("读取\(label)", "Read \(label)"), read))
        if previous == value { return }
        do {
            _ = try await query(L("设置\(label)", "Set \(label)"), { try write(value, $0) })
            let actual = try parse(try await query(L("回读\(label)", "Read back \(label)"), read))
            guard accept?(actual) ?? (actual == value) else {
                throw RazerError.invalidResponse(L("\(label)回读为 \(actual)，期望 \(value)", "\(label) read back as \(actual), expected \(value)"))
            }
        } catch {
            _ = try? await query(L("恢复\(label)", "Restore \(label)"), { try write(previous, $0) })
            throw error
        }
    }
}

// MARK: Chroma lighting (class 0x10 / legacy 0x0F)

public struct ChromaState: Sendable {
    public init() {}
    public var brightnessPercent: Int?
    public var effect: ChromaEffect?
    public var colors: [RazerColor] = []
    public var batteryPercent: Int?
    public var charging: Bool?
    public var firmware: String?
    public var serial: String?
    public var errors: [String] = []
}

public final class ChromaDevice: Protocol25Device, @unchecked Sendable {
    public let category: DeviceCategory
    /// Legacy keyboards use class 0x0F effects and have no brightness command.
    public let legacy: Bool

    public init(productId: UInt16, name: String, category: DeviceCategory, legacy: Bool, endpoint: FeatureEndpoint) {
        self.category = category
        self.legacy = legacy
        super.init(productId: productId, name: name, endpoint: endpoint, tag: String(format: "chroma-%04X", productId))
    }

    public var supportedEffects: [ChromaEffect] { legacy ? [.off, .static, .breathing, .spectrum] : ChromaEffect.allCases }
    public var supportsBrightness: Bool { !legacy }

    public func readState(includeIdentity: Bool = true) async -> ChromaState {
        var state = ChromaState()
        var errors: [String] = []
        if !legacy {
            state.brightnessPercent = await probe(L("亮度", "Brightness"), &errors, ChromaProtocol.getBrightness, ChromaProtocol.readBrightnessPercent)
        }
        let effect = legacy
            ? await probe(L("灯效", "Lighting effect"), &errors, ChromaProtocol.getLegacyEffect, ChromaProtocol.readLegacyEffect)
            : await probe(L("灯效", "Lighting effect"), &errors, ChromaProtocol.getEffect, ChromaProtocol.readEffect)
        state.effect = effect?.effect
        state.colors = effect?.colors ?? []
        if includeIdentity {
            // Identity and battery are optional: lamps, docks and wired mice ignore these classes.
            var ignored: [String] = []
            state.firmware = await probe(L("固件", "Firmware"), &ignored, KeyboardProtocol25.getFirmware, KeyboardProtocol25.readFirmware)
            state.serial = await probe(L("序列号", "Serial number"), &ignored, KeyboardProtocol25.getSerial, KeyboardProtocol25.readSerial)
            state.batteryPercent = await probe(L("电量", "Battery"), &ignored, KeyboardProtocol25.getBattery, KeyboardProtocol25.readBatteryPercent)
            if state.batteryPercent != nil {
                state.charging = await probe(L("充电", "Charging"), &ignored, KeyboardProtocol25.getCharging, KeyboardProtocol25.readCharging)
            }
        }
        state.errors = errors
        return state
    }

    public func setBrightness(percent: Int) async throws {
        guard !legacy else { throw RazerError.notSupported(L("该设备的 0x0F 灯光没有亮度命令", "This device's 0x0F lighting has no brightness command")) }
        try await verifiedWrite(
            L("亮度", "Brightness"), read: ChromaProtocol.getBrightness, parse: ChromaProtocol.readBrightnessPercent,
            write: { value, txn in try ChromaProtocol.setBrightness(txn, level: ChromaProtocol.brightnessLevel(percent: value)) },
            value: percent, accept: { abs($0 - percent) <= 1 })
    }

    public func setEffect(_ effect: ChromaEffect, colors: [RazerColor]) async throws {
        let palette = Array(colors.prefix(effect.colorCount))
        if legacy {
            let previous = try? ChromaProtocol.readLegacyEffect(try await query(L("读取灯效", "Read effect"), ChromaProtocol.getLegacyEffect))
            if previous?.effect == effect, previous?.colors == palette { return }
            _ = try await query(L("设置灯效", "Set effect")) { try ChromaProtocol.setLegacyEffect($0, effect, colors: palette) }
            // Wired keyboards never read the effect in the middleware, so a write is verified
            // only when this firmware answers the read.
            guard let previous,
                  let stored = try? ChromaProtocol.readLegacyEffect(try await query(L("回读灯效", "Read back effect"), ChromaProtocol.getLegacyEffect)),
                  stored.effect != effect
            else { return }
            if let old = previous.effect {
                _ = try? await query(L("恢复灯效", "Restore effect")) { try ChromaProtocol.setLegacyEffect($0, old, colors: previous.colors) }
            }
            throw RazerError.invalidResponse(L("灯效回读不一致", "Effect read-back mismatch"))
        }
        let previous = try ChromaProtocol.readEffect(try await query(L("读取灯效", "Read effect"), ChromaProtocol.getEffect))
        if previous.effect == effect, previous.colors == palette { return }
        do {
            _ = try await query(L("设置灯效", "Set effect")) { try ChromaProtocol.setEffect($0, effect, colors: palette) }
            let actual = try ChromaProtocol.readEffect(try await query(L("回读灯效", "Read back effect"), ChromaProtocol.getEffect))
            guard actual.effect == effect else {
                throw RazerError.invalidResponse(L("灯效回读为 \(actual.effect?.displayName ?? "未知")", "Effect read back as \(actual.effect?.displayName ?? "unknown")"))
            }
        } catch {
            if let old = previous.effect {
                _ = try? await query(L("恢复灯效", "Restore effect")) { try ChromaProtocol.setEffect($0, old, colors: previous.colors) }
            }
            throw error
        }
    }
}

// MARK: Protocol 25 keyboards

public struct Keyboard25State: Sendable {
    public init() {}
    public var firmware: String?
    public var serial: String?
    public var batteryPercent: Int?
    public var charging: Bool?
    public var gameMode: Bool?
    public var pollingRate: Int?
    public var errors: [String] = []
}

public final class Keyboard25Device: Protocol25Device, @unchecked Sendable {
    public let lighting: ChromaDevice

    public init(productId: UInt16, name: String, endpoint: FeatureEndpoint) {
        lighting = ChromaDevice(productId: productId, name: name, category: .keyboard,
                                legacy: ProductLists.legacyChromaKeyboards.contains(productId), endpoint: endpoint)
        super.init(productId: productId, name: name, endpoint: endpoint, tag: String(format: "keyboard-%04X", productId))
    }

    public static let pollingRateOptions = KeyboardProtocol25.pollingRates.map(\.hertz).sorted()

    public func readState() async -> Keyboard25State {
        var state = Keyboard25State()
        var errors: [String] = []
        state.firmware = await probe(L("固件", "Firmware"), &errors, KeyboardProtocol25.getFirmware, KeyboardProtocol25.readFirmware)
        var serialErrors: [String] = []
        state.serial = await probe(L("序列号", "Serial number"), &serialErrors, KeyboardProtocol25.getSerial, KeyboardProtocol25.readSerial)
        if state.serial?.isEmpty ?? true {
            state.serial = await probe(L("序列号", "Serial number"), &serialErrors, KeyboardProtocol25.getSerialAlt, KeyboardProtocol25.readSerial)
        }
        if state.serial?.isEmpty ?? true { state.serial = endpoint.interface.serialNumber }
        var optional: [String] = []
        state.batteryPercent = await probe(L("电量", "Battery"), &optional, KeyboardProtocol25.getBattery, KeyboardProtocol25.readBatteryPercent)
        state.charging = await probe(L("充电", "Charging"), &optional, KeyboardProtocol25.getCharging, KeyboardProtocol25.readCharging)
        state.gameMode = await probe(L("游戏模式", "Game mode"), &errors, KeyboardProtocol25.getGameMode) { try KeyboardProtocol25.readGameMode($0).gameMode != 0 }
        state.pollingRate = await probe(L("回报率", "Polling rate"), &errors, KeyboardProtocol25.getPollingRate, KeyboardProtocol25.readPollingRate) ?? nil
        state.errors = errors
        return state
    }

    public func setGameMode(_ enabled: Bool) async throws {
        let previous = try KeyboardProtocol25.readGameMode(try await query(L("读取游戏模式", "Read game mode"), KeyboardProtocol25.getGameMode))
        let desired: UInt8 = enabled ? 1 : 0
        if previous.gameMode == desired { return }
        do {
            _ = try await query(L("设置游戏模式", "Set game mode")) {
                try KeyboardProtocol25.setGameMode($0, gameMode: desired, keyCover: previous.keyCover, lifted: previous.lifted)
            }
            let actual = try KeyboardProtocol25.readGameMode(try await query(L("回读游戏模式", "Read back game mode"), KeyboardProtocol25.getGameMode))
            guard actual.gameMode == desired else { throw RazerError.invalidResponse(L("游戏模式回读不一致", "Game mode read-back mismatch")) }
        } catch {
            _ = try? await query(L("恢复游戏模式", "Restore game mode")) {
                try KeyboardProtocol25.setGameMode($0, gameMode: previous.gameMode, keyCover: previous.keyCover, lifted: previous.lifted)
            }
            throw error
        }
    }

    public func setPollingRate(_ hertz: Int) async throws {
        guard let code = KeyboardProtocol25.pollingCode(hertz) else {
            throw RazerError.invalidArgument(L("不支持的回报率 \(hertz) Hz", "Unsupported polling rate \(hertz) Hz"))
        }
        let previous = try KeyboardProtocol25.readPollingRate(try await query(L("读取回报率", "Read polling rate"), KeyboardProtocol25.getPollingRate))
        if previous == hertz { return }
        do {
            _ = try await query(L("设置回报率", "Set polling rate")) { try KeyboardProtocol25.setPollingRate($0, code: code) }
            let actual = try KeyboardProtocol25.readPollingRate(try await query(L("回读回报率", "Read back polling rate"), KeyboardProtocol25.getPollingRate))
            guard actual == hertz else { throw RazerError.invalidResponse(L("回报率回读为 \(actual.map(String.init) ?? "未知")", "Polling rate read back as \(actual.map(String.init) ?? "unknown")")) }
        } catch {
            if let previous, let restore = KeyboardProtocol25.pollingCode(previous) {
                _ = try? await query(L("恢复回报率", "Restore polling rate")) { try KeyboardProtocol25.setPollingRate($0, code: restore) }
            }
            throw error
        }
    }
}

// MARK: Protocol 25 audio

public struct HeadsetAudioState: Sendable {
    public init() {}
    public var firmware: String?
    public var batteryPercent: Int?
    public var charging: Bool?
    public var eqPreset: UInt8?
    public var eqBands: [UInt8]?
    public var bass: UInt8?
    public var micMuted: Bool?
    public var micVolume: UInt8?
    public var audioSource: AudioSource?
    public var noiseSuppression: Bool?
    public var ancState: AncState?
    public var ancLevel: UInt8?
    public var errors: [String] = []
}

public final class HeadsetAudioDevice: Protocol25Device, @unchecked Sendable {
    public let category: DeviceCategory
    public static var presets: [(value: UInt8, name: String)] { HeadsetAudioProtocol.presets }
    public static let tenBandFrequencies = HeadsetAudioProtocol.tenBandFrequencies

    public init(productId: UInt16, name: String, endpoint: FeatureEndpoint) {
        category = ProductLists.audioCategory(productId)
        super.init(productId: productId, name: name, endpoint: endpoint, tag: String(format: "audio-%04X", productId))
    }

    public func readState() async -> HeadsetAudioState {
        var s = HeadsetAudioState()
        var e: [String] = []
        typealias P = HeadsetAudioProtocol
        s.firmware = await probe(L("固件", "Firmware"), &e, P.getFirmware, KeyboardProtocol25.readFirmware)
        s.batteryPercent = await probe(L("电量", "Battery"), &e, P.getBattery, KeyboardProtocol25.readBatteryPercent)
        s.charging = await probe(L("充电", "Charging"), &e, P.getCharging, KeyboardProtocol25.readCharging)
        s.eqPreset = await probe(L("均衡器预设", "EQ preset"), &e, P.getEqPreset, P.readSecond)
        s.bass = await probe(L("低音", "Bass"), &e, P.getBass, P.readSecond)
        s.micMuted = await probe(L("麦克风静音", "Microphone mute"), &e, P.getMicMute) { try P.readSecond($0) != 0 }
        s.micVolume = await probe(L("麦克风音量", "Microphone volume"), &e, P.getMicVolume, P.readSecond)
        s.audioSource = await probe(L("音源", "Audio source"), &e, P.getAudioSource) { AudioSource(rawValue: try P.readSecond($0)) } ?? nil
        s.noiseSuppression = await probe(L("降噪", "Noise suppression"), &e, P.getNoiseSuppression) { try P.readSecond($0) != 0 }
        var bandErrors: [String] = []
        s.eqBands = await probe(L("均衡器", "Equaliser"), &bandErrors, { try P.getEqBands($0, tenBand: true) }) { try P.readEqBands($0, tenBand: true) }
        if s.eqBands == nil {
            s.eqBands = await probe(L("均衡器（8 段）", "Equaliser (8 bands)"), &bandErrors, { try P.getEqBands($0, tenBand: false) }) {
                try P.readEqBands($0, tenBand: false)
            }
            if s.eqBands == nil { e.append(contentsOf: bandErrors) }
        }
        if let anc = await probe(L("主动降噪", "Active noise cancelling"), &e, P.getAnc, P.readAnc) {
            s.ancState = anc.state
            s.ancLevel = anc.level
        }
        s.errors = e
        return s
    }

    public func setEqPreset(_ preset: UInt8) async throws {
        try await verifiedWrite(L("均衡器预设", "EQ preset"), read: HeadsetAudioProtocol.getEqPreset, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setEqPreset($1, $0) }, value: preset)
    }

    public func setEqBands(_ bands: [UInt8]) async throws {
        let tenBand = bands.count == 10
        try await verifiedWrite(L("均衡器", "Equaliser"), read: { try HeadsetAudioProtocol.getEqBands($0, tenBand: tenBand) },
                                parse: { try HeadsetAudioProtocol.readEqBands($0, tenBand: tenBand) },
                                write: { try HeadsetAudioProtocol.setEqBands($1, $0) }, value: bands)
    }

    public func setBass(_ level: UInt8) async throws {
        guard level <= 100 else { throw RazerError.invalidArgument(L("低音需在 0 到 100 之间", "Bass must be between 0 and 100")) }
        try await verifiedWrite(L("低音", "Bass"), read: HeadsetAudioProtocol.getBass, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setBass($1, $0) }, value: level)
    }

    public func setMicMute(_ muted: Bool) async throws {
        try await verifiedWrite(L("麦克风静音", "Microphone mute"), read: HeadsetAudioProtocol.getMicMute, parse: { try HeadsetAudioProtocol.readSecond($0) != 0 },
                                write: { try HeadsetAudioProtocol.setMicMute($1, $0) }, value: muted)
    }

    public func setMicVolume(_ volume: UInt8) async throws {
        guard volume <= 100 else { throw RazerError.invalidArgument(L("麦克风音量需在 0 到 100 之间", "Microphone volume must be between 0 and 100")) }
        try await verifiedWrite(L("麦克风音量", "Microphone volume"), read: HeadsetAudioProtocol.getMicVolume, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setMicVolume($1, $0) }, value: volume)
    }

    public func setAudioSource(_ source: AudioSource) async throws {
        try await verifiedWrite(L("音源", "Audio source"), read: HeadsetAudioProtocol.getAudioSource,
                                parse: { AudioSource(rawValue: try HeadsetAudioProtocol.readSecond($0)) },
                                write: { value, txn in try HeadsetAudioProtocol.setAudioSource(txn, value ?? .none) },
                                value: Optional(source))
    }

    public func setNoiseSuppression(_ enabled: Bool) async throws {
        try await verifiedWrite(L("降噪", "Noise suppression"), read: HeadsetAudioProtocol.getNoiseSuppression,
                                parse: { try HeadsetAudioProtocol.readSecond($0) != 0 },
                                write: { try HeadsetAudioProtocol.setNoiseSuppression($1, $0) }, value: enabled)
    }

    public func setAnc(_ state: AncState, level: UInt8) async throws {
        guard level <= 10 else { throw RazerError.invalidArgument(L("降噪强度需在 0 到 10 之间", "Noise-cancelling level must be between 0 and 10")) }
        struct Anc: Equatable { let state: AncState?; let level: UInt8 }
        try await verifiedWrite(
            L("主动降噪", "Active noise cancelling"), read: HeadsetAudioProtocol.getAnc,
            parse: { let value = try HeadsetAudioProtocol.readAnc($0); return Anc(state: value.state, level: value.level) },
            write: { value, txn in try HeadsetAudioProtocol.setAnc(txn, value.state ?? .off, level: value.level) },
            value: Anc(state: state, level: level),
            accept: { $0.state == state && (state != .on || $0.level == level) })
    }
}

// MARK: Kraken lighting

public final class KrakenDevice: @unchecked Sendable {
    public let productId: UInt16
    public let model: ProductLists.KrakenModel
    public let channel: ReportChannel

    public init(productId: UInt16, model: ProductLists.KrakenModel, channel: ReportChannel) {
        self.productId = productId
        self.model = model
        self.channel = channel
    }

    public func setLighting(_ settings: LightingSettings) async throws {
        guard model.effects.contains(settings.effect) else {
            throw RazerError.notSupported(L("\(model.name) 不支持\(settings.effect.displayName)", "\(model.name) does not support \(settings.effect.displayName)"))
        }
        let layout = model.layout
        let reports: [[UInt8]]
        switch settings.effect {
        case .off: reports = KrakenProtocol.off(layout)
        case .static: reports = KrakenProtocol.staticColor(layout, settings.primary, writeColor: model.writesColor)
        case .spectrum: reports = KrakenProtocol.spectrum(layout)
        case .breathingSingle: reports = try KrakenProtocol.breathing(layout, [settings.primary])
        case .breathingDual: reports = try KrakenProtocol.breathing(layout, [settings.primary, settings.secondary])
        case .breathingTriple: reports = try KrakenProtocol.breathing(layout, [settings.primary, settings.secondary, settings.tertiary])
        case .custom: reports = KrakenProtocol.custom(layout, settings.primary)
        default: throw RazerError.notSupported(settings.effect.displayName)
        }
        let custom = settings.effect == .custom
        try await channel.send(reports, delay: { custom ? 0 : Double($0[2]) * 0.015 })
    }
}

// MARK: BlackShark V3 Pro

public struct BlackSharkState: Sendable {
    public init() {}
    public var batteryPercent: Int?
    public var charging: Bool?
    public var sidetone: Int?
    public var thx: Bool?
    public var ancMode: BlackSharkAncMode?
    public var ancLevel: Int?
    public var gameChat: Int?
}

public final class BlackSharkDevice: @unchecked Sendable {
    public let productId: UInt16
    /// Looked up on each read so the name follows the interface language.
    public var name: String {
        ProductLists.blackSharkProtocolHeadsets[productId]?.name ?? ProductLists.blackSharkName(productId)
    }
    public private(set) var wireless: Bool
    public let channel: ReportChannel
    /// Controls verified on this model. The Kraken V4 Pro acknowledges THX writes without
    /// applying them and reports ANC without its level, so those stay read-only there.
    public let supportsThx: Bool
    public let supportsAncWrite: Bool
    private var woke = false
    private var directionResolved = false

    public init(productId: UInt16, channel: ReportChannel) {
        self.productId = productId
        self.channel = channel
        if let model = ProductLists.blackSharkProtocolHeadsets[productId] {
            supportsThx = model.thx
            supportsAncWrite = model.ancWrite
            wireless = model.wireless
        } else {
            supportsThx = true
            supportsAncWrite = true
            // Only observed PIDs map to a direction; unknown variants start on the wireless byte.
            wireless = !ProductLists.blackSharkWired.contains(productId)
        }
    }

    /// The link byte selects the headset behind a receiver (0x80) or the device on the cable
    /// (0x00). The side that is not there answers 0xFF, so pick the one that answers a value.
    private func resolveDirection() async throws {
        guard !directionResolved else { return }
        for candidate in [wireless, !wireless] {
            wireless = candidate
            if try await read(BlackSharkProtocol.batteryClass) != nil {
                // Resolved only once something answers, so a headset that is switched on
                // after the hub was found is picked up on the next refresh.
                directionResolved = true
                DiagnosticLog.shared.write("blackshark-\(String(format: "%04X", productId))",
                                           L("链路字节：\(candidate ? "0x80（无线）" : "0x00（有线）")", "Link byte: \(candidate ? "0x80 (wireless)" : "0x00 (wired)")"))
                return
            }
        }
        wireless = !wireless
    }

    private func wake() async throws {
        guard !woke else { return }
        try await channel.send(BlackSharkProtocol.wakeSequence, delay: { _ in 0.002 })
        woke = true
    }

    private func read(_ commandClass: UInt8) async throws -> [UInt8]? {
        try await wake()
        let request = BlackSharkProtocol.create(commandClass, 0x00, wireless: wireless)
        let reply = try await channel.exchange(request, timeout: 1.0) { report in
            guard let parsed = BlackSharkProtocol.parse(report) else { return false }
            return parsed.commandClass == commandClass && parsed.subtype == 0x01
        }
        // 0xFF in the first argument means "no device on this link".
        guard let reply, let parsed = BlackSharkProtocol.parse(reply), let first = parsed.arguments.first, first != 0xFF
        else { return nil }
        return parsed.arguments
    }

    private func readRetry(_ commandClass: UInt8) async throws -> [UInt8]? {
        for _ in 0..<3 {
            if let value = try await read(commandClass) { return value }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        return nil
    }

    public func readState() async throws -> BlackSharkState {
        try await resolveDirection()
        var state = BlackSharkState()
        state.batteryPercent = try await read(BlackSharkProtocol.batteryClass).map { Int($0[0]) }
        state.charging = try await read(BlackSharkProtocol.chargingClass).map { $0[0] != 0 }
        state.sidetone = try await read(BlackSharkProtocol.sidetoneRead).map { Int($0[0]) }
        if supportsThx {
            state.thx = try await read(BlackSharkProtocol.thxClass).map { $0[0] != 0 }
        }
        if let anc = try await read(BlackSharkProtocol.ancRead) {
            state.ancMode = BlackSharkAncMode(rawValue: anc[0])
            state.ancLevel = anc.count >= 2 ? Int(anc[1]) : nil
        }
        state.gameChat = try await read(BlackSharkProtocol.gameChatRead).map { Int($0[0]) }
        return state
    }

    private func write(_ report: [UInt8], readClass: UInt8, restore: (([UInt8]) -> [UInt8])?, verify: ([UInt8]?) -> Bool) async throws {
        let previous = try await read(readClass)
        do {
            try await channel.send([report])
            guard verify(try await readRetry(readClass)) else {
                throw RazerError.invalidResponse(L("回读与设置值不一致", "Read-back does not match the value set"))
            }
        } catch {
            if let previous, let restore {
                try? await channel.send([restore(previous)])
            }
            throw error
        }
    }

    public func setSidetone(_ level: Int) async throws {
        guard (0...15).contains(level) else { throw RazerError.invalidArgument(L("侧音需在 0 到 15 之间", "Sidetone must be between 0 and 15")) }
        try await write(BlackSharkProtocol.create(BlackSharkProtocol.sidetoneSet, 0x01, wireless: wireless, [UInt8(level), 0]),
                        readClass: BlackSharkProtocol.sidetoneRead,
                        restore: { BlackSharkProtocol.create(BlackSharkProtocol.sidetoneSet, 0x01, wireless: self.wireless, [$0[0], 0]) },
                        verify: { $0?.first == UInt8(level) })
    }

    public func setThx(_ enabled: Bool) async throws {
        try await write(BlackSharkProtocol.create(BlackSharkProtocol.thxClass, 0x01, wireless: wireless, [enabled ? 1 : 0, 0]),
                        readClass: BlackSharkProtocol.thxClass,
                        restore: { BlackSharkProtocol.create(BlackSharkProtocol.thxClass, 0x01, wireless: self.wireless, [$0[0] != 0 ? 1 : 0, 0]) },
                        verify: { ($0?.first).map { ($0 != 0) == enabled } ?? false })
    }

    public func setAnc(_ mode: BlackSharkAncMode, level: Int) async throws {
        let normalized = mode == .anc ? min(max(level, 1), 4) : mode == .ambient ? 1 : 0
        try await write(BlackSharkProtocol.create(BlackSharkProtocol.ancSet, 0x02, wireless: wireless, [mode.rawValue, UInt8(normalized)]),
                        readClass: BlackSharkProtocol.ancRead,
                        restore: { old in BlackSharkProtocol.create(BlackSharkProtocol.ancSet, 0x02, wireless: self.wireless,
                                                                    [old[0], old.count > 1 ? old[1] : 1]) },
                        verify: { value in
                            guard let value, value.count >= 2 else { return false }
                            return value[0] == mode.rawValue && (mode != .anc || Int(value[1]) == normalized)
                        })
    }

    public func setGameChat(_ balance: Int) async throws {
        guard (0...20).contains(balance) else { throw RazerError.invalidArgument(L("游戏/聊天平衡需在 0 到 20 之间", "Game/chat balance must be between 0 and 20")) }
        try await write(BlackSharkProtocol.create(BlackSharkProtocol.gameChatSet, 0x01, wireless: wireless, [UInt8(balance), 0]),
                        readClass: BlackSharkProtocol.gameChatRead,
                        restore: { BlackSharkProtocol.create(BlackSharkProtocol.gameChatSet, 0x01, wireless: self.wireless, [$0[0], 0]) },
                        verify: { $0?.first == UInt8(balance) })
    }
}
