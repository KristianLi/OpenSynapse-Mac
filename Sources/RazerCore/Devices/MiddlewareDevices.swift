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
            return try parse(try await query("读取\(label)", make))
        } catch {
            errors.append("\(label)：\(error.localizedDescription)")
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
        let previous = try parse(try await query("读取\(label)", read))
        if previous == value { return }
        do {
            _ = try await query("设置\(label)", { try write(value, $0) })
            let actual = try parse(try await query("回读\(label)", read))
            guard accept?(actual) ?? (actual == value) else {
                throw RazerError.invalidResponse("\(label)回读为 \(actual)，期望 \(value)")
            }
        } catch {
            _ = try? await query("恢复\(label)", { try write(previous, $0) })
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
            state.brightnessPercent = await probe("亮度", &errors, ChromaProtocol.getBrightness, ChromaProtocol.readBrightnessPercent)
        }
        let effect = legacy
            ? await probe("灯效", &errors, ChromaProtocol.getLegacyEffect, ChromaProtocol.readLegacyEffect)
            : await probe("灯效", &errors, ChromaProtocol.getEffect, ChromaProtocol.readEffect)
        state.effect = effect?.effect
        state.colors = effect?.colors ?? []
        if includeIdentity {
            // Identity and battery are optional: lamps, docks and wired mice ignore these classes.
            var ignored: [String] = []
            state.firmware = await probe("固件", &ignored, KeyboardProtocol25.getFirmware, KeyboardProtocol25.readFirmware)
            state.serial = await probe("序列号", &ignored, KeyboardProtocol25.getSerial, KeyboardProtocol25.readSerial)
            state.batteryPercent = await probe("电量", &ignored, KeyboardProtocol25.getBattery, KeyboardProtocol25.readBatteryPercent)
            if state.batteryPercent != nil {
                state.charging = await probe("充电", &ignored, KeyboardProtocol25.getCharging, KeyboardProtocol25.readCharging)
            }
        }
        state.errors = errors
        return state
    }

    public func setBrightness(percent: Int) async throws {
        guard !legacy else { throw RazerError.notSupported("该设备的 0x0F 灯光没有亮度命令") }
        try await verifiedWrite(
            "亮度", read: ChromaProtocol.getBrightness, parse: ChromaProtocol.readBrightnessPercent,
            write: { value, txn in try ChromaProtocol.setBrightness(txn, level: ChromaProtocol.brightnessLevel(percent: value)) },
            value: percent, accept: { abs($0 - percent) <= 1 })
    }

    public func setEffect(_ effect: ChromaEffect, colors: [RazerColor]) async throws {
        let palette = Array(colors.prefix(effect.colorCount))
        if legacy {
            let previous = try? ChromaProtocol.readLegacyEffect(try await query("读取灯效", ChromaProtocol.getLegacyEffect))
            if previous?.effect == effect, previous?.colors == palette { return }
            _ = try await query("设置灯效") { try ChromaProtocol.setLegacyEffect($0, effect, colors: palette) }
            // Wired keyboards never read the effect in the middleware, so a write is verified
            // only when this firmware answers the read.
            guard let previous,
                  let stored = try? ChromaProtocol.readLegacyEffect(try await query("回读灯效", ChromaProtocol.getLegacyEffect)),
                  stored.effect != effect
            else { return }
            if let old = previous.effect {
                _ = try? await query("恢复灯效") { try ChromaProtocol.setLegacyEffect($0, old, colors: previous.colors) }
            }
            throw RazerError.invalidResponse("灯效回读不一致")
        }
        let previous = try ChromaProtocol.readEffect(try await query("读取灯效", ChromaProtocol.getEffect))
        if previous.effect == effect, previous.colors == palette { return }
        do {
            _ = try await query("设置灯效") { try ChromaProtocol.setEffect($0, effect, colors: palette) }
            let actual = try ChromaProtocol.readEffect(try await query("回读灯效", ChromaProtocol.getEffect))
            guard actual.effect == effect else {
                throw RazerError.invalidResponse("灯效回读为 \(actual.effect?.displayName ?? "未知")")
            }
        } catch {
            if let old = previous.effect {
                _ = try? await query("恢复灯效") { try ChromaProtocol.setEffect($0, old, colors: previous.colors) }
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
        state.firmware = await probe("固件", &errors, KeyboardProtocol25.getFirmware, KeyboardProtocol25.readFirmware)
        var serialErrors: [String] = []
        state.serial = await probe("序列号", &serialErrors, KeyboardProtocol25.getSerial, KeyboardProtocol25.readSerial)
        if state.serial?.isEmpty ?? true {
            state.serial = await probe("序列号", &serialErrors, KeyboardProtocol25.getSerialAlt, KeyboardProtocol25.readSerial)
        }
        if state.serial?.isEmpty ?? true { state.serial = endpoint.interface.serialNumber }
        var optional: [String] = []
        state.batteryPercent = await probe("电量", &optional, KeyboardProtocol25.getBattery, KeyboardProtocol25.readBatteryPercent)
        state.charging = await probe("充电", &optional, KeyboardProtocol25.getCharging, KeyboardProtocol25.readCharging)
        state.gameMode = await probe("游戏模式", &errors, KeyboardProtocol25.getGameMode) { try KeyboardProtocol25.readGameMode($0).gameMode != 0 }
        state.pollingRate = await probe("回报率", &errors, KeyboardProtocol25.getPollingRate, KeyboardProtocol25.readPollingRate) ?? nil
        state.errors = errors
        return state
    }

    public func setGameMode(_ enabled: Bool) async throws {
        let previous = try KeyboardProtocol25.readGameMode(try await query("读取游戏模式", KeyboardProtocol25.getGameMode))
        let desired: UInt8 = enabled ? 1 : 0
        if previous.gameMode == desired { return }
        do {
            _ = try await query("设置游戏模式") {
                try KeyboardProtocol25.setGameMode($0, gameMode: desired, keyCover: previous.keyCover, lifted: previous.lifted)
            }
            let actual = try KeyboardProtocol25.readGameMode(try await query("回读游戏模式", KeyboardProtocol25.getGameMode))
            guard actual.gameMode == desired else { throw RazerError.invalidResponse("游戏模式回读不一致") }
        } catch {
            _ = try? await query("恢复游戏模式") {
                try KeyboardProtocol25.setGameMode($0, gameMode: previous.gameMode, keyCover: previous.keyCover, lifted: previous.lifted)
            }
            throw error
        }
    }

    public func setPollingRate(_ hertz: Int) async throws {
        guard let code = KeyboardProtocol25.pollingCode(hertz) else {
            throw RazerError.invalidArgument("不支持的回报率 \(hertz) Hz")
        }
        let previous = try KeyboardProtocol25.readPollingRate(try await query("读取回报率", KeyboardProtocol25.getPollingRate))
        if previous == hertz { return }
        do {
            _ = try await query("设置回报率") { try KeyboardProtocol25.setPollingRate($0, code: code) }
            let actual = try KeyboardProtocol25.readPollingRate(try await query("回读回报率", KeyboardProtocol25.getPollingRate))
            guard actual == hertz else { throw RazerError.invalidResponse("回报率回读为 \(actual.map(String.init) ?? "未知")") }
        } catch {
            if let previous, let restore = KeyboardProtocol25.pollingCode(previous) {
                _ = try? await query("恢复回报率") { try KeyboardProtocol25.setPollingRate($0, code: restore) }
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
    public static let presets = HeadsetAudioProtocol.presets
    public static let tenBandFrequencies = HeadsetAudioProtocol.tenBandFrequencies

    public init(productId: UInt16, name: String, endpoint: FeatureEndpoint) {
        category = ProductLists.audioCategory(productId)
        super.init(productId: productId, name: name, endpoint: endpoint, tag: String(format: "audio-%04X", productId))
    }

    public func readState() async -> HeadsetAudioState {
        var s = HeadsetAudioState()
        var e: [String] = []
        typealias P = HeadsetAudioProtocol
        s.firmware = await probe("固件", &e, P.getFirmware, KeyboardProtocol25.readFirmware)
        s.batteryPercent = await probe("电量", &e, P.getBattery, KeyboardProtocol25.readBatteryPercent)
        s.charging = await probe("充电", &e, P.getCharging, KeyboardProtocol25.readCharging)
        s.eqPreset = await probe("均衡器预设", &e, P.getEqPreset, P.readSecond)
        s.bass = await probe("低音", &e, P.getBass, P.readSecond)
        s.micMuted = await probe("麦克风静音", &e, P.getMicMute) { try P.readSecond($0) != 0 }
        s.micVolume = await probe("麦克风音量", &e, P.getMicVolume, P.readSecond)
        s.audioSource = await probe("音源", &e, P.getAudioSource) { AudioSource(rawValue: try P.readSecond($0)) } ?? nil
        s.noiseSuppression = await probe("降噪", &e, P.getNoiseSuppression) { try P.readSecond($0) != 0 }
        var bandErrors: [String] = []
        s.eqBands = await probe("均衡器", &bandErrors, { try P.getEqBands($0, tenBand: true) }) { try P.readEqBands($0, tenBand: true) }
        if s.eqBands == nil {
            s.eqBands = await probe("均衡器（8 段）", &bandErrors, { try P.getEqBands($0, tenBand: false) }) {
                try P.readEqBands($0, tenBand: false)
            }
            if s.eqBands == nil { e.append(contentsOf: bandErrors) }
        }
        if let anc = await probe("主动降噪", &e, P.getAnc, P.readAnc) {
            s.ancState = anc.state
            s.ancLevel = anc.level
        }
        s.errors = e
        return s
    }

    public func setEqPreset(_ preset: UInt8) async throws {
        try await verifiedWrite("均衡器预设", read: HeadsetAudioProtocol.getEqPreset, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setEqPreset($1, $0) }, value: preset)
    }

    public func setEqBands(_ bands: [UInt8]) async throws {
        let tenBand = bands.count == 10
        try await verifiedWrite("均衡器", read: { try HeadsetAudioProtocol.getEqBands($0, tenBand: tenBand) },
                                parse: { try HeadsetAudioProtocol.readEqBands($0, tenBand: tenBand) },
                                write: { try HeadsetAudioProtocol.setEqBands($1, $0) }, value: bands)
    }

    public func setBass(_ level: UInt8) async throws {
        guard level <= 100 else { throw RazerError.invalidArgument("低音需在 0 到 100 之间") }
        try await verifiedWrite("低音", read: HeadsetAudioProtocol.getBass, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setBass($1, $0) }, value: level)
    }

    public func setMicMute(_ muted: Bool) async throws {
        try await verifiedWrite("麦克风静音", read: HeadsetAudioProtocol.getMicMute, parse: { try HeadsetAudioProtocol.readSecond($0) != 0 },
                                write: { try HeadsetAudioProtocol.setMicMute($1, $0) }, value: muted)
    }

    public func setMicVolume(_ volume: UInt8) async throws {
        guard volume <= 100 else { throw RazerError.invalidArgument("麦克风音量需在 0 到 100 之间") }
        try await verifiedWrite("麦克风音量", read: HeadsetAudioProtocol.getMicVolume, parse: HeadsetAudioProtocol.readSecond,
                                write: { try HeadsetAudioProtocol.setMicVolume($1, $0) }, value: volume)
    }

    public func setAudioSource(_ source: AudioSource) async throws {
        try await verifiedWrite("音源", read: HeadsetAudioProtocol.getAudioSource,
                                parse: { AudioSource(rawValue: try HeadsetAudioProtocol.readSecond($0)) },
                                write: { value, txn in try HeadsetAudioProtocol.setAudioSource(txn, value ?? .none) },
                                value: Optional(source))
    }

    public func setNoiseSuppression(_ enabled: Bool) async throws {
        try await verifiedWrite("降噪", read: HeadsetAudioProtocol.getNoiseSuppression,
                                parse: { try HeadsetAudioProtocol.readSecond($0) != 0 },
                                write: { try HeadsetAudioProtocol.setNoiseSuppression($1, $0) }, value: enabled)
    }

    public func setAnc(_ state: AncState, level: UInt8) async throws {
        guard level <= 10 else { throw RazerError.invalidArgument("降噪强度需在 0 到 10 之间") }
        struct Anc: Equatable { let state: AncState?; let level: UInt8 }
        try await verifiedWrite(
            "主动降噪", read: HeadsetAudioProtocol.getAnc,
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
            throw RazerError.notSupported("\(model.name) 不支持\(settings.effect.displayName)")
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
    public let name: String
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
            name = model.name
            supportsThx = model.thx
            supportsAncWrite = model.ancWrite
            wireless = model.wireless
        } else {
            name = ProductLists.blackSharkName(productId)
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
                                           "链路字节：\(candidate ? "0x80（无线）" : "0x00（有线）")")
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
                throw RazerError.invalidResponse("回读与设置值不一致")
            }
        } catch {
            if let previous, let restore {
                try? await channel.send([restore(previous)])
            }
            throw error
        }
    }

    public func setSidetone(_ level: Int) async throws {
        guard (0...15).contains(level) else { throw RazerError.invalidArgument("侧音需在 0 到 15 之间") }
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
        guard (0...20).contains(balance) else { throw RazerError.invalidArgument("游戏/聊天平衡需在 0 到 20 之间") }
        try await write(BlackSharkProtocol.create(BlackSharkProtocol.gameChatSet, 0x01, wireless: wireless, [UInt8(balance), 0]),
                        readClass: BlackSharkProtocol.gameChatRead,
                        restore: { BlackSharkProtocol.create(BlackSharkProtocol.gameChatSet, 0x01, wireless: self.wireless, [$0[0], 0]) },
                        verify: { $0?.first == UInt8(balance) })
    }
}
