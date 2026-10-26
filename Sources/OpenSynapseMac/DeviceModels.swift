import Observation
import RazerCore
import SwiftUI

/// Busy flag, status line and error banner shared by every device page.
@MainActor
@Observable
class PageModel {
    var busy = false
    var loaded = false
    var status: String?
    var error: String?

    func run(_ label: String, _ body: () async throws -> String?) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            status = try await body() ?? "\(label)已应用"
        } catch {
            self.error = "\(label)失败：\(error.localizedDescription)"
            status = nil
        }
    }
}

extension RazerColor {
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8((ns.redComponent * 255).rounded().clamped(0, 255)),
                  UInt8((ns.greenComponent * 255).rounded().clamped(0, 255)),
                  UInt8((ns.blueComponent * 255).rounded().clamped(0, 255)))
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { Swift.min(Swift.max(self, low), high) }
}

// MARK: OpenRazer

@MainActor
@Observable
final class OpenRazerModel: PageModel {
    let device: OpenRazerDevice
    var state = OpenRazerState()

    var dpiX = 800.0
    var dpiY = 800.0
    var dpiLinked = true
    var pollingRate = 1000
    var stages: [DpiStage] = []
    var activeStage: UInt8 = 1
    var idleMinutes = 5.0
    var lowBattery = 10
    var brightness: [LedZone: Double] = [:]
    var lightingZone: LedZone = .all
    var lighting: [LedZone: LightingSettings] = [:]
    var matrixColor = RazerColor.razerGreen
    var scrollMode: ScrollMode = .tactile
    var scrollAcceleration = false
    var smartReel = false
    var keyswitch: KeyswitchOptimization = .gaming
    var hyperPollingMode = 1

    init(device: OpenRazerDevice) {
        self.device = device
        super.init()
        let zones = device.lightingZones.values.filter { !$0.effects.isEmpty }.map(\.zone).sorted()
        lightingZone = zones.contains(device.definition.defaultLedZone) ? device.definition.defaultLedZone : zones.first ?? .all
        for zone in zones {
            let effects = device.lightingZones[zone]!.orderedEffects
            let initial = effects.first { $0 == .static } ?? effects.first { $0 != .off } ?? .off
            lighting[zone] = LightingSettings(effect: initial)
        }
    }

    /// A write whose paired read the firmware refused (0x05/0x03) almost always fails the
    /// same way, so it is hidden along with the read.
    private static let pairedReads: [Capability: Capability] = [
        .scrollModeWrite: .scrollModeRead, .scrollAccelerationWrite: .scrollAccelerationRead,
        .smartReelWrite: .smartReelRead, .keyswitchOptimizationWrite: .keyswitchOptimizationRead,
        .idleTimeoutWrite: .idleTimeoutRead, .lowBatteryThresholdWrite: .lowBatteryThresholdRead,
        .dpiStagesWrite: .dpiStagesRead, .pollingRateWrite: .pollingRateRead, .dpiWrite: .dpiRead,
    ]

    func has(_ capability: Capability) -> Bool {
        guard device.has(capability), !state.unsupported.contains(capability) else { return false }
        if let read = Self.pairedReads[capability], state.unsupported.contains(read) { return false }
        return true
    }

    /// Zones whose brightness read the device rejected (e.g. the matrix-wide zone 0x00 on
    /// mice that only light the logo and wheel) are not offered.
    private func zoneResponds(_ caps: LightingZoneCapabilities) -> Bool {
        !loaded || !caps.canReadBrightness || state.brightness[caps.zone] != nil
    }

    var effectZones: [LightingZoneCapabilities] {
        let zones = device.lightingZones.values.filter { !$0.effects.isEmpty }.sorted { $0.zone < $1.zone }
        let responding = zones.filter(zoneResponds)
        return responding.isEmpty ? zones : responding
    }

    var brightnessZones: [LightingZoneCapabilities] {
        device.lightingZones.values.filter { $0.canWriteBrightness && zoneResponds($0) }.sorted { $0.zone < $1.zone }
    }

    func load() async {
        busy = true
        defer { busy = false }
        if !loaded, device.has(.deviceModeWrite) {
            _ = try? await device.ensureDriverMode()
        }
        state = await device.readState()
        loaded = true
        if let dpi = state.dpi {
            dpiX = Double(dpi.x)
            dpiY = Double(dpi.y)
            dpiLinked = dpi.x == dpi.y
        }
        if let rate = state.pollingRate { pollingRate = rate }
        if let value = state.dpiStages {
            stages = value.stages
            activeStage = value.activeStage
        }
        if let idle = state.idleSeconds { idleMinutes = Double(idle) / 60 }
        if let threshold = state.lowBatteryThreshold { lowBattery = min(max((threshold + 2) / 5 * 5, 5), 25) }
        for (zone, value) in state.brightness { brightness[zone] = Double(value) }
        for zone in brightnessZones.map(\.zone) where brightness[zone] == nil { brightness[zone] = 255 }
        if let mode = state.scrollMode { scrollMode = mode }
        if let value = state.scrollAcceleration { scrollAcceleration = value }
        if let value = state.smartReel { smartReel = value }
        if let value = state.keyswitch { keyswitch = value }
        if !effectZones.contains(where: { $0.zone == lightingZone }), let first = effectZones.first {
            lightingZone = first.zone
        }
        error = state.errors.isEmpty ? nil : state.errors.joined(separator: "\n")
        status = "已读取设备状态"
    }

    func refreshBattery() async {
        guard !busy else { return }
        if let value = try? await device.readBatteryOnly() {
            state.batteryPercent = value.percent
            state.charging = value.charging ?? state.charging
        }
    }

    func applyDpi() async {
        let x = Int(dpiX.rounded())
        let y = dpiLinked ? x : Int(dpiY.rounded())
        await run("DPI") {
            if let actual = try await device.setDpi(x: x, y: y) {
                state.dpi = actual
                dpiX = Double(actual.x)
                dpiY = Double(actual.y)
                return actual == (x, y) ? "DPI 已设为 \(actual.x) × \(actual.y)" : "设备当前 DPI 为 \(actual.x) × \(actual.y)（与设置值不同）"
            }
            return nil
        }
    }

    func applyPollingRate(_ hertz: Int) async {
        await run("回报率") {
            let actual = try await device.setPollingRate(hertz)
            if let actual {
                pollingRate = actual
                state.pollingRate = actual
                return actual == hertz ? "回报率已设为 \(actual) Hz" : "设备当前回报率为 \(actual) Hz（未接受 \(hertz) Hz）"
            }
            pollingRate = hertz
            return nil
        }
    }

    func applyStages() async {
        let renumbered = stages.enumerated().map { DpiStage(number: UInt8($0.offset + 1), x: $0.element.x, y: $0.element.y) }
        let active = min(max(activeStage, 1), UInt8(renumbered.count))
        await run("DPI 档位") {
            try await device.setDpiStages(DpiStages(activeStage: active, stages: renumbered))
            stages = renumbered
            activeStage = active
            return nil
        }
    }

    func addStage() {
        guard stages.count < 5 else { return }
        let last = stages.last?.x ?? 800
        let value = min(last * 2, device.maximumDpi)
        stages.append(DpiStage(number: UInt8(stages.count + 1), x: value, y: value))
    }

    func removeStage(at index: Int) {
        guard stages.count > 1, stages.indices.contains(index) else { return }
        stages.remove(at: index)
        if Int(activeStage) > stages.count { activeStage = UInt8(stages.count) }
    }

    func applyIdle() async {
        let seconds = Int((idleMinutes * 60).rounded())
        await run("休眠时间") {
            try await device.setIdleTime(seconds: min(max(seconds, 60), 900))
            return nil
        }
    }

    func applyLowBattery() async {
        await run("低电量提醒") {
            try await device.setLowBatteryThreshold(percent: lowBattery)
            return nil
        }
    }

    func applyBrightness(_ zone: LedZone) async {
        let value = UInt8((brightness[zone] ?? 255).rounded().clamped(0, 255))
        await run("\(zone.displayName)亮度") {
            try await device.setBrightness(value, zone: zone)
            return "\(zone.displayName)亮度已设为 \(Int(Double(value) / 255 * 100))%"
        }
    }

    func applyLighting() async {
        guard var settings = lighting[lightingZone] else { return }
        settings.zone = lightingZone
        await run("灯效") {
            try await device.setLighting(settings)
            return "\(lightingZone.displayName)：\(settings.effect.displayName)"
        }
    }

    func applyMatrixColor() async {
        await run("整键盘颜色") {
            try await device.setMatrixColor(matrixColor)
            return nil
        }
    }

    func applyScrollMode() async { await run("滚轮模式") { try await device.setScrollMode(scrollMode); return nil } }
    func applyScrollAcceleration() async { await run("滚轮加速") { try await device.setScrollAcceleration(scrollAcceleration); return nil } }
    func applySmartReel() async { await run("智能滚轮") { try await device.setSmartReel(smartReel); return nil } }
    func applyKeyswitch() async { await run("按键优化") { try await device.setKeyswitchOptimization(keyswitch); return nil } }
    func applyHyperPolling() async {
        await run("接收器指示灯") { try await device.setHyperPollingIndicator(mode: UInt8(hyperPollingMode)); return nil }
    }
}

// MARK: Protocol 25 keyboards

@MainActor
@Observable
final class KeyboardModel: PageModel {
    let device: Keyboard25Device
    var state = Keyboard25State()
    var gameMode = false
    var pollingRate = 1000
    let lighting: ChromaModel

    init(device: Keyboard25Device) {
        self.device = device
        lighting = ChromaModel(device: device.lighting, identity: false)
    }

    func load() async {
        busy = true
        defer { busy = false }
        state = await device.readState()
        loaded = true
        if let value = state.gameMode { gameMode = value }
        if let value = state.pollingRate { pollingRate = value }
        error = state.errors.isEmpty ? nil : state.errors.joined(separator: "\n")
        status = "已读取设备状态"
        await lighting.load()
    }

    func applyGameMode() async { await run("游戏模式") { try await device.setGameMode(gameMode); return nil } }

    func applyPollingRate(_ hertz: Int) async {
        await run("回报率") {
            try await device.setPollingRate(hertz)
            pollingRate = hertz
            return "回报率已设为 \(hertz) Hz"
        }
    }
}

// MARK: Chroma lighting

@MainActor
@Observable
final class ChromaModel: PageModel {
    let device: ChromaDevice
    let identity: Bool
    var state = ChromaState()
    var effect: ChromaEffect = .static
    var colors: [RazerColor] = [.razerGreen, RazerColor(0, 0x90, 0xFF)]
    var brightness = 70.0

    init(device: ChromaDevice, identity: Bool = true) {
        self.device = device
        self.identity = identity
    }

    func load() async {
        busy = true
        defer { busy = false }
        state = await device.readState(includeIdentity: identity)
        loaded = true
        if let value = state.effect { effect = value }
        for (index, color) in state.colors.prefix(2).enumerated() { colors[index] = color }
        if let value = state.brightnessPercent { brightness = Double(value) }
        error = state.errors.isEmpty ? nil : state.errors.joined(separator: "\n")
    }

    func applyEffect() async {
        await run("灯效") {
            try await device.setEffect(effect, colors: colors)
            return "灯效：\(effect.displayName)"
        }
    }

    func applyBrightness() async {
        await run("亮度") {
            try await device.setBrightness(percent: Int(brightness.rounded()))
            return "亮度已设为 \(Int(brightness.rounded()))%"
        }
    }
}

// MARK: Audio

@MainActor
@Observable
final class AudioModel: PageModel {
    let device: HeadsetAudioDevice
    let lighting: KrakenModel?
    var state = HeadsetAudioState()
    var preset: UInt8 = 0
    var bands: [Double] = []
    var bass = 0.0
    var micMuted = false
    var micVolume = 50.0
    var source: AudioSource = .usb
    var noiseSuppression = false
    var ancState: AncState = .off
    var ancLevel = 5

    init(device: HeadsetAudioDevice, lighting: KrakenModel?) {
        self.device = device
        self.lighting = lighting
    }

    func load() async {
        busy = true
        defer { busy = false }
        state = await device.readState()
        loaded = true
        if let value = state.eqPreset { preset = value }
        if let value = state.eqBands { bands = value.map(Double.init) }
        if let value = state.bass { bass = Double(value) }
        if let value = state.micMuted { micMuted = value }
        if let value = state.micVolume { micVolume = Double(value) }
        if let value = state.audioSource { source = value }
        if let value = state.noiseSuppression { noiseSuppression = value }
        if let value = state.ancState { ancState = value }
        if let value = state.ancLevel { ancLevel = Int(value) }
        status = state.errors.isEmpty ? "已读取设备状态" : "部分项目设备未回答，已隐藏"
    }

    func applyPreset() async { await run("均衡器预设") { try await device.setEqPreset(preset); return nil } }
    func applyBands() async {
        await run("均衡器") { try await device.setEqBands(bands.map { UInt8($0.rounded().clamped(0, 100)) }); return nil }
    }
    func applyBass() async { await run("低音增强") { try await device.setBass(UInt8(bass.rounded())); return nil } }
    func applyMicMute() async { await run("麦克风静音") { try await device.setMicMute(micMuted); return nil } }
    func applyMicVolume() async { await run("麦克风音量") { try await device.setMicVolume(UInt8(micVolume.rounded())); return nil } }
    func applySource() async { await run("音源") { try await device.setAudioSource(source); return nil } }
    func applyNoiseSuppression() async { await run("降噪") { try await device.setNoiseSuppression(noiseSuppression); return nil } }
    func applyAnc() async { await run("主动降噪") { try await device.setAnc(ancState, level: UInt8(ancLevel)); return nil } }
}

// MARK: Kraken

@MainActor
@Observable
final class KrakenModel: PageModel {
    let device: KrakenDevice
    var settings: LightingSettings

    init(device: KrakenDevice) {
        self.device = device
        settings = LightingSettings(effect: device.model.effects.contains(.static) ? .static : device.model.effects[0])
    }

    func apply() async {
        await run("灯效") {
            try await device.setLighting(settings)
            return "灯效：\(settings.effect.displayName)"
        }
    }
}

// MARK: BlackShark

@MainActor
@Observable
final class BlackSharkModel: PageModel {
    let device: BlackSharkDevice
    var state = BlackSharkState()
    var sidetone = 0.0
    var thx = false
    var ancMode: BlackSharkAncMode = .off
    var ancLevel = 2
    var gameChat = 10.0

    let lighting: LampArrayModel?

    init(device: BlackSharkDevice, lighting: LampArrayModel?) {
        self.device = device
        self.lighting = lighting
    }

    func load() async {
        busy = true
        defer { busy = false }
        do {
            state = try await device.readState()
            loaded = true
            if let value = state.sidetone { sidetone = Double(value) }
            if let value = state.thx { thx = value }
            if let value = state.ancMode { ancMode = value }
            if let value = state.ancLevel { ancLevel = min(max(value, 1), 4) }
            if let value = state.gameChat { gameChat = Double(value) }
            error = nil
            status = state.batteryPercent == nil ? "耳机没有回答，可能处于休眠或未开机" : "已读取设备状态"
        } catch {
            loaded = true
            self.error = "读取失败：\(error.localizedDescription)"
        }
    }

    func applySidetone() async { await run("侧音") { try await device.setSidetone(Int(sidetone.rounded())); return nil } }
    func applyThx() async { await run("THX 空间音效") { try await device.setThx(thx); return nil } }
    func applyAnc() async { await run("降噪模式") { try await device.setAnc(ancMode, level: ancLevel); return nil } }
    func applyGameChat() async { await run("游戏/聊天平衡") { try await device.setGameChat(Int(gameChat.rounded())); return nil } }
}

// MARK: HID LampArray

@MainActor
@Observable
final class LampArrayModel: PageModel {
    let device: LampArrayDevice
    var color = RazerColor.razerGreen
    var brightness = 100.0

    init(device: LampArrayDevice) {
        self.device = device
    }

    private var intensity: UInt8 { UInt8((brightness / 100 * 255).rounded().clamped(0, 255)) }

    func apply() async {
        await run("灯光") {
            try await device.setColor(color, brightness: intensity)
            return "已把 \(device.lampCount) 个灯设为所选颜色"
        }
    }

    func off() async {
        await run("关灯") {
            try await device.off()
            return "灯光已关闭"
        }
    }

    func restoreDeviceEffect() async {
        await run("恢复设备灯效") {
            try await device.restoreDeviceEffect()
            return "已交还给设备自带灯效"
        }
    }
}
