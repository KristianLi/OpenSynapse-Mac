import Foundation

public enum LightingEffect: String, CaseIterable, Sendable, Identifiable {
    case off, `static`, spectrum, wave, reactive, blinking
    case breathingRandom, breathingSingle, breathingDual, breathingTriple
    case starlightRandom, starlightSingle, starlightDual
    case wheel, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "关闭"
        case .static: "静态"
        case .spectrum: "光谱循环"
        case .wave: "波浪"
        case .reactive: "触发反应"
        case .blinking: "闪烁"
        case .breathingRandom: "呼吸（随机色）"
        case .breathingSingle: "呼吸（单色）"
        case .breathingDual: "呼吸（双色）"
        case .breathingTriple: "呼吸（三色）"
        case .starlightRandom: "星光（随机色）"
        case .starlightSingle: "星光（单色）"
        case .starlightDual: "星光（双色）"
        case .wheel: "轮转"
        case .custom: "自定义帧"
        }
    }

    /// How many user colors the effect takes.
    public var colorCount: Int {
        switch self {
        case .static, .reactive, .blinking, .breathingSingle, .starlightSingle, .custom: 1
        case .breathingDual, .starlightDual: 2
        case .breathingTriple: 3
        default: 0
        }
    }

    public var usesSpeed: Bool {
        switch self {
        case .reactive, .starlightRandom, .starlightSingle, .starlightDual: true
        default: false
        }
    }

    public var usesDirection: Bool { self == .wave || self == .wheel }
}

public struct LightingSettings: Equatable, Sendable {
    public var effect: LightingEffect
    public var speed: UInt8 = 2
    public var direction: UInt8 = 1
    public var primary: RazerColor = .razerGreen
    public var secondary: RazerColor = RazerColor(0, 0x90, 0xFF)
    public var tertiary: RazerColor = RazerColor(0xFF, 0x30, 0x30)
    public var storage: Storage?
    public var zone: LedZone?

    public init(
        effect: LightingEffect,
        speed: UInt8 = 2,
        direction: UInt8 = 1,
        primary: RazerColor = .razerGreen,
        secondary: RazerColor = RazerColor(0, 0x90, 0xFF),
        tertiary: RazerColor = RazerColor(0xFF, 0x30, 0x30),
        storage: Storage? = nil,
        zone: LedZone? = nil
    ) {
        self.effect = effect
        self.speed = speed
        self.direction = direction
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.storage = storage
        self.zone = zone
    }
}

/// Resolves a lighting operation to exactly one OpenRazer builder family (standard, extended
/// or mouse-extended matrix) and one LED zone, the same way OpenSynapse does. A device only
/// gets a control when the catalog facts pin the builder unambiguously.
enum LightingProtocol {
    static let standardPrefix = "razer_chroma_standard_matrix_effect_"
    static let extendedPrefix = "razer_chroma_extended_matrix_effect_"
    static let mousePrefix = "razer_chroma_mouse_extended_matrix_effect_"

    static let brightnessWriteBuilders = [
        "razer_chroma_extended_matrix_brightness",
        "razer_chroma_standard_set_led_brightness",
        "razer_chroma_misc_set_blade_brightness",
        "razer_chroma_misc_set_dock_brightness",
    ]
    static let brightnessReadBuilders = [
        "razer_chroma_extended_matrix_get_brightness",
        "razer_chroma_standard_get_led_brightness",
        "razer_chroma_misc_get_blade_brightness",
        "razer_chroma_misc_get_dock_brightness",
    ]

    static func createEffect(_ device: DeviceDefinition, _ settings: LightingSettings) throws -> RazerRequest {
        let suffix = try effectSuffix(settings.effect)
        var storage = (settings.storage ?? device.defaultStorage).rawValue
        let candidates = effectBuilders(suffix)
        let selection: (builder: String, zone: LedZone)
        if settings.effect == .custom, let customZone = settings.zone {
            selection = try selectDefaultEffect(device, settings.effect, candidates, storage)
            guard selection.zone == customZone else {
                throw RazerError.notSupported("\(device.productIdText) 的自定义帧不在灯区 \(customZone.displayName)")
            }
        } else if let zone = settings.zone {
            selection = (try selectBuilder(device, candidates, storage, zone), zone)
        } else {
            selection = try selectDefaultEffect(device, settings.effect, candidates, storage)
        }
        let (builder, zone) = selection

        if settings.effect == .custom {
            let fixedStorage = builder.hasPrefix(standardPrefix)
                ? try device.requiredFixedArgument(builder, index: 0)
                : Storage.temporary.rawValue
            if let requested = settings.storage, requested.rawValue != fixedStorage {
                throw RazerError.notSupported("\(device.productIdText) 的自定义帧要求固定存储区")
            }
            storage = fixedStorage
        }

        if builder.hasPrefix(standardPrefix) {
            return try createStandard(device, builder, settings, storage)
        }
        if builder.hasPrefix(extendedPrefix) {
            return try createExtended(device, builder, settings, storage, zone)
        }
        return try createMouse(device, builder, settings, storage, zone)
    }

    static func createEffectRequests(_ device: DeviceDefinition, _ settings: LightingSettings) throws -> [RazerRequest] {
        do {
            return [try createEffect(device, settings)]
        } catch RazerError.notSupported(let message) {
            guard canCreateClassicEffect(device, settings) else {
                throw RazerError.notSupported(message)
            }
            return try createClassicEffect(device, settings)
        }
    }

    static func getBrightness(_ device: DeviceDefinition, storage: Storage?, zone: LedZone?) throws -> RazerRequest {
        let actualStorage = (storage ?? device.defaultStorage).rawValue
        let candidates = brightnessReadBuilders
        let actualZone = try resolveZone(device, candidates, actualStorage, zone)
        let builder = try selectBuilder(device, candidates, actualStorage, actualZone)
        switch builder {
        case "razer_chroma_extended_matrix_get_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x03, commandClass: 0x0F, commandId: 0x84,
                                               arguments: [actualStorage, actualZone.rawValue])
        case "razer_chroma_misc_get_blade_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x02, commandClass: 0x0E, commandId: 0x84, arguments: [0x01])
        case "razer_chroma_misc_get_dock_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x01, commandClass: 0x07, commandId: 0x82)
        default:
            return try StandardProtocol.getLedBrightness(device, storage: actualStorage, zone: actualZone.rawValue)
        }
    }

    static func setBrightness(_ device: DeviceDefinition, storage: Storage?, zone: LedZone?, brightness: UInt8) throws -> RazerRequest {
        let actualStorage = (storage ?? device.defaultStorage).rawValue
        let candidates = brightnessWriteBuilders
        let actualZone = try resolveZone(device, candidates, actualStorage, zone)
        let builder = try selectBuilder(device, candidates, actualStorage, actualZone)
        switch builder {
        case "razer_chroma_extended_matrix_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x03, commandClass: 0x0F, commandId: 0x04,
                                               arguments: [actualStorage, actualZone.rawValue, brightness])
        case "razer_chroma_misc_set_blade_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x02, commandClass: 0x0E, commandId: 0x04,
                                               arguments: [0x01, brightness])
        case "razer_chroma_misc_set_dock_brightness":
            return try StandardProtocol.create(device, builder, dataSize: 0x01, commandClass: 0x07, commandId: 0x02,
                                               arguments: [brightness])
        default:
            return try StandardProtocol.setLedBrightness(device, storage: actualStorage, zone: actualZone.rawValue, brightness: brightness)
        }
    }

    /// Brightness responses carry the level in a builder-specific argument slot.
    static func parseBrightness(_ request: RazerRequest, _ response: RazerReport) throws -> UInt8 {
        switch request.builder {
        case "razer_chroma_misc_get_dock_brightness":
            return try response.successfulArguments(minimumLength: 1).first!
        case "razer_chroma_misc_get_blade_brightness":
            return Array(try response.successfulArguments(minimumLength: 2))[1]
        default:
            _ = try response.successfulArguments(minimumLength: 2)
            return Array(response.rawArguments)[2]
        }
    }

    static func setCustomRow(_ device: DeviceDefinition, row: UInt8, startColumn: UInt8, colors: [RazerColor]) throws -> RazerRequest {
        guard (1...25).contains(colors.count), Int(startColumn) + colors.count - 1 <= 255 else {
            throw RazerError.invalidArgument("一行最多 25 个颜色")
        }
        if let matrix = device.matrixDimensions,
           row >= matrix.rows || Int(startColumn) + colors.count > Int(matrix.columns) {
            throw RazerError.invalidArgument("自定义行超出设备矩阵")
        }
        let stopColumn = UInt8(Int(startColumn) + colors.count - 1)
        let rgb = colors.flatMap(\.bytes)
        if device.transactions["razer_chroma_standard_matrix_set_custom_frame"] != nil {
            return try StandardProtocol.create(device, "razer_chroma_standard_matrix_set_custom_frame", dataSize: 0x46,
                                               commandClass: 0x03, commandId: 0x0B,
                                               arguments: [0xFF, row, startColumn, stopColumn] + rgb,
                                               allowArgumentsBeyondDeclaredSize: true)
        }
        let builder = device.transactions["razer_chroma_extended_matrix_set_custom_frame2"] != nil
            ? "razer_chroma_extended_matrix_set_custom_frame2"
            : "razer_chroma_extended_matrix_set_custom_frame"
        let arguments: [UInt8] = [0x00, 0x00, row, startColumn, stopColumn] + rgb
        let dataSize: UInt8 = builder.hasSuffix("2") ? UInt8(arguments.count) : 0x47
        return try StandardProtocol.create(device, builder, dataSize: dataSize, commandClass: 0x0F, commandId: 0x03,
                                           arguments: arguments, allowArgumentsBeyondDeclaredSize: arguments.count > Int(dataSize))
    }

    private static func createStandard(
        _ device: DeviceDefinition, _ builder: String, _ value: LightingSettings, _ storage: UInt8
    ) throws -> RazerRequest {
        let speed = min(max(value.speed, 1), 4)
        let starSpeed = min(max(value.speed, 1), 3)
        let p = value.primary.bytes
        let s = value.secondary.bytes
        let arguments: [UInt8]
        switch value.effect {
        case .off: arguments = [0x00]
        case .wave: arguments = [0x01, min(max(value.direction, 1), 2)]
        case .spectrum: arguments = [0x04]
        case .reactive: arguments = [0x02, speed] + p
        case .static: arguments = [0x06] + p
        case .starlightRandom: arguments = [0x19, 0x03, starSpeed]
        case .starlightSingle: arguments = [0x19, 0x01, starSpeed] + p + [0, 0, 0]
        case .starlightDual: arguments = [0x19, 0x02, starSpeed] + p + s
        case .breathingRandom: arguments = [0x03, 0x03, 0, 0, 0, 0, 0, 0]
        case .breathingSingle: arguments = [0x03, 0x01] + p + [0, 0, 0]
        case .breathingDual: arguments = [0x03, 0x02] + p + s
        case .custom: arguments = [0x05, storage]
        default: throw RazerError.notSupported("标准灯光协议不支持\(value.effect.displayName)")
        }
        let starlight = [.starlightRandom, .starlightSingle, .starlightDual].contains(value.effect)
        let declared: UInt8 = starlight ? 1 : UInt8(arguments.count)
        return try StandardProtocol.create(device, builder, dataSize: declared, commandClass: 0x03, commandId: 0x0A,
                                           arguments: arguments, allowArgumentsBeyondDeclaredSize: arguments.count > Int(declared))
    }

    private static func createExtended(
        _ device: DeviceDefinition, _ builder: String, _ value: LightingSettings, _ storage: UInt8, _ zone: LedZone
    ) throws -> RazerRequest {
        let p = value.primary.bytes
        let s = value.secondary.bytes
        let starSpeed = min(max(value.speed, 1), 3)
        let tail: [UInt8]
        switch value.effect {
        case .off: tail = [0x00, 0, 0, 0]
        case .static: tail = [0x01, 0, 0, 1] + p
        case .wave: tail = [0x04, min(value.direction, 2), 0x28, 0]
        case .spectrum: tail = [0x03, 0, 0, 0]
        case .wheel: tail = [0x0A, min(max(value.direction, 1), 2), 0x28, 0]
        case .reactive: tail = [0x05, 0, min(max(value.speed, 1), 4), 1] + p
        case .breathingRandom: tail = [0x02, 0, 0, 0]
        case .breathingSingle: tail = [0x02, 1, 0, 1] + p
        case .breathingDual: tail = [0x02, 2, 0, 2] + p + s
        case .starlightRandom: tail = [0x07, 0, starSpeed, 0]
        case .starlightSingle: tail = [0x07, 0, starSpeed, 1] + p
        case .starlightDual: tail = [0x07, 0, starSpeed, 2] + p + s
        case .custom: tail = [0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        default: throw RazerError.notSupported("扩展灯光协议不支持\(value.effect.displayName)")
        }
        let arguments = value.effect == .custom ? [0x00, 0x00] + tail : [storage, zone.rawValue] + tail
        return try StandardProtocol.create(device, builder, dataSize: UInt8(arguments.count), commandClass: 0x0F, commandId: 0x02,
                                           arguments: arguments)
    }

    private static func createMouse(
        _ device: DeviceDefinition, _ builder: String, _ value: LightingSettings, _ storage: UInt8, _ zone: LedZone
    ) throws -> RazerRequest {
        let p = value.primary.bytes
        let s = value.secondary.bytes
        let tail: [UInt8]
        switch value.effect {
        case .off: tail = [0x00]
        case .static: tail = [0x06] + p
        case .spectrum: tail = [0x04]
        case .reactive: tail = [0x02, min(max(value.speed, 1), 4)] + p
        case .breathingRandom: tail = [0x03, 0x03, 0, 0, 0, 0, 0, 0]
        case .breathingSingle: tail = [0x03, 0x01] + p + [0, 0, 0]
        case .breathingDual: tail = [0x03, 0x02] + p + s
        default: throw RazerError.notSupported("鼠标灯光协议不支持\(value.effect.displayName)")
        }
        let arguments = [storage, zone.rawValue] + tail
        return try StandardProtocol.create(device, builder, dataSize: UInt8(arguments.count), commandClass: 0x03, commandId: 0x0D,
                                           arguments: arguments)
    }

    static func selectBuilder(_ device: DeviceDefinition, _ candidates: [String], _ storage: UInt8, _ zone: LedZone) throws -> String {
        let scored = candidates
            .filter { device.transactions[$0] != nil }
            .map { (builder: $0, score: scoreBuilder(device, $0, storage, zone)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        guard let best = scored.first, scored.count == 1 || scored[0].score != scored[1].score else {
            throw RazerError.notSupported("\(device.productIdText) 无法把该灯光操作确定到唯一的协议族")
        }
        return best.builder
    }

    private static func scoreBuilder(_ device: DeviceDefinition, _ builder: String, _ storage: UInt8, _ zone: LedZone) -> Int {
        if let prefixes = device.builderArgumentPrefixes[builder] {
            if prefixes.contains(where: { $0.count >= 2 && $0[0] == storage && $0[1] == zone.rawValue }) {
                return 4
            }
            if prefixes.contains(where: { $0.count == 1 && $0[0] == storage }) {
                return 3
            }
            return 0
        }
        if builder.hasPrefix(standardPrefix) {
            return zone == device.defaultLedZone ? 2 : 0
        }
        let family: String? = builder.hasPrefix(extendedPrefix) ? extendedPrefix
            : builder.hasPrefix(mousePrefix) ? mousePrefix : nil
        if let family {
            if builder.hasSuffix("custom_frame"), zone == device.defaultLedZone {
                return 2
            }
            return familyZones(device, family, storage).contains(zone) ? 2 : 0
        }
        if builder.contains("_blade_brightness"), device.category == .laptop {
            return zone == device.defaultLedZone ? 2 : 0
        }
        if builder.contains("_dock_brightness") {
            return zone == device.defaultLedZone ? 2 : 0
        }
        return 1
    }

    /// Zones that sibling builders of one effect family declare for a storage.
    private static func familyZones(_ device: DeviceDefinition, _ family: String, _ storage: UInt8) -> [LedZone] {
        let prefixes = device.builderArgumentPrefixes
            .filter { $0.key.hasPrefix(family) }
            .flatMap(\.value)
        var zones: [LedZone] = []
        for prefix in prefixes where prefix.count >= 2 && prefix[0] == storage {
            if let zone = LedZone(rawValue: prefix[1]), !zones.contains(zone) {
                zones.append(zone)
            }
        }
        if prefixes.contains(where: { $0.count == 1 && $0[0] == storage }), !zones.contains(device.defaultLedZone) {
            zones.append(device.defaultLedZone)
        }
        return zones
    }

    static func resolveEffectZone(
        _ device: DeviceDefinition, _ effect: LightingEffect, storage: Storage? = nil, zone: LedZone? = nil
    ) throws -> LedZone {
        do {
            let builders = effectBuilders(try effectSuffix(effect))
            let actualStorage = (storage ?? device.defaultStorage).rawValue
            if let zone {
                return try resolveZone(device, builders, actualStorage, zone)
            }
            return try selectDefaultEffect(device, effect, builders, actualStorage).zone
        } catch {
            let settings = LightingSettings(effect: effect, storage: storage, zone: zone)
            guard canCreateClassicEffect(device, settings) else {
                throw error
            }
            return zone ?? device.defaultLedZone
        }
    }

    static func resolveBrightnessZone(_ device: DeviceDefinition, write: Bool, storage: Storage? = nil, zone: LedZone? = nil) throws -> LedZone {
        try resolveZone(device, write ? brightnessWriteBuilders : brightnessReadBuilders,
                        (storage ?? device.defaultStorage).rawValue, zone)
    }

    private static func resolveZone(_ device: DeviceDefinition, _ candidates: [String], _ storage: UInt8, _ requested: LedZone?) throws -> LedZone {
        if let requested {
            _ = try selectBuilder(device, candidates, storage, requested)
            return requested
        }
        var zones: [LedZone] = [device.defaultLedZone]
        for builder in candidates {
            for prefix in device.builderArgumentPrefixes[builder] ?? [] where prefix.count >= 2 && prefix[0] == storage {
                if let zone = LedZone(rawValue: prefix[1]), !zones.contains(zone) {
                    zones.append(zone)
                }
            }
        }
        for zone in zones {
            if (try? selectBuilder(device, candidates, storage, zone)) != nil {
                return zone
            }
        }
        throw RazerError.notSupported("\(device.productIdText) 没有支持该灯光操作的灯区")
    }

    static func effectSuffix(_ effect: LightingEffect) throws -> String {
        switch effect {
        case .off: "none"
        case .static: "static"
        case .spectrum: "spectrum"
        case .wave: "wave"
        case .reactive: "reactive"
        case .blinking: "blinking"
        case .breathingRandom: "breathing_random"
        case .breathingSingle: "breathing_single"
        case .breathingDual: "breathing_dual"
        case .starlightRandom: "starlight_random"
        case .starlightSingle: "starlight_single"
        case .starlightDual: "starlight_dual"
        case .wheel: "wheel"
        case .custom: "custom_frame"
        case .breathingTriple: throw RazerError.notSupported("标准 OpenRazer 灯光协议不支持三色呼吸")
        }
    }

    private static func effectBuilders(_ suffix: String) -> [String] {
        [standardPrefix + suffix, extendedPrefix + suffix, mousePrefix + suffix]
    }

    private static func selectDefaultEffect(
        _ device: DeviceDefinition, _ effect: LightingEffect, _ candidates: [String], _ storage: UInt8
    ) throws -> (builder: String, zone: LedZone) {
        guard device.has(try genericEffectCapability(effect)) else {
            throw RazerError.notSupported("\(device.productIdText) 没有整机级的\(effect.displayName)效果")
        }
        // Standard first, then mouse-extended, then extended: the order OpenRazer's generic
        // effect attributes resolve to.
        let priority = [candidates[0], candidates[2], candidates[1]]
        for builder in priority where device.transactions[builder] != nil {
            if let zone = builderZones(device, builder, storage).first {
                return (builder, zone)
            }
        }
        throw RazerError.notSupported("\(device.productIdText) 的\(effect.displayName)没有确定的默认协议")
    }

    private static func builderZones(_ device: DeviceDefinition, _ builder: String, _ storage: UInt8) -> [LedZone] {
        if builder.hasPrefix(standardPrefix) {
            return [device.defaultLedZone]
        }
        if let prefixes = device.builderArgumentPrefixes[builder] {
            var exact: [LedZone] = []
            for prefix in prefixes where prefix.count >= 2 && prefix[0] == storage {
                if let zone = LedZone(rawValue: prefix[1]), !exact.contains(zone) {
                    exact.append(zone)
                }
            }
            if !exact.isEmpty {
                return exact
            }
            if prefixes.contains(where: { $0.count == 1 && $0[0] == storage }) {
                return [device.defaultLedZone]
            }
        }
        let family: String? = builder.hasPrefix(mousePrefix) ? mousePrefix
            : builder.hasPrefix(extendedPrefix) ? extendedPrefix : nil
        guard let family else {
            return []
        }
        if builder.hasSuffix("custom_frame") {
            // The extended custom-frame selector has fixed wire arguments 00 00; the physical
            // target remains the device's declared matrix zone.
            return [device.defaultLedZone]
        }
        return familyZones(device, family, storage)
    }

    static func genericEffectCapability(_ effect: LightingEffect) throws -> String {
        switch effect {
        case .off: "set_none_effect"
        case .static: "set_static_effect"
        case .spectrum: "set_spectrum_effect"
        case .wave: "set_wave_effect"
        case .reactive: "set_reactive_effect"
        case .blinking: "set_blinking_effect"
        case .breathingRandom: "set_breath_random_effect"
        case .breathingSingle: "set_breath_single_effect"
        case .breathingDual: "set_breath_dual_effect"
        case .starlightRandom: "set_starlight_random_effect"
        case .starlightSingle: "set_starlight_single_effect"
        case .starlightDual: "set_starlight_dual_effect"
        case .wheel: "set_wheel_effect"
        case .custom: "set_custom_effect"
        case .breathingTriple: throw RazerError.notSupported("三色呼吸没有通用能力")
        }
    }

    static func canCreateClassicEffect(_ device: DeviceDefinition, _ settings: LightingSettings) -> Bool {
        guard settings.effect != .breathingTriple,
              let capability = try? genericEffectCapability(settings.effect),
              device.has(capability)
        else {
            return false
        }
        let storage = (settings.storage ?? device.defaultStorage).rawValue
        let zone = (settings.zone ?? device.defaultLedZone).rawValue
        let builders: [String]
        switch settings.effect {
        case .off: builders = ["razer_chroma_standard_set_led_state"]
        case .spectrum: builders = ["razer_chroma_standard_set_led_state", "razer_chroma_standard_set_led_effect"]
        case .static, .breathingSingle, .blinking:
            builders = ["razer_chroma_standard_set_led_state", "razer_chroma_standard_set_led_rgb", "razer_chroma_standard_set_led_effect"]
        default: builders = []
        }
        return !builders.isEmpty && builders.allSatisfy { builder in
            device.transactions[builder] != nil
                && (device.builderArgumentPrefixes[builder] ?? []).contains { prefix in
                    prefix.count >= 1 && prefix[0] == storage && (prefix.count == 1 || prefix[1] == zone)
                }
        }
    }

    private static func createClassicEffect(_ device: DeviceDefinition, _ settings: LightingSettings) throws -> [RazerRequest] {
        let storage = (settings.storage ?? device.defaultStorage).rawValue
        let zone = (settings.zone ?? device.defaultLedZone).rawValue
        if settings.effect == .off {
            return [try StandardProtocol.setLedState(device, storage: storage, zone: zone, enabled: false)]
        }
        var requests = [try StandardProtocol.setLedState(device, storage: storage, zone: zone, enabled: true)]
        if [.static, .breathingSingle, .blinking].contains(settings.effect) {
            requests.append(try StandardProtocol.setLedColor(device, storage: storage, zone: zone, color: settings.primary))
        }
        let classic: ClassicLedEffect
        switch settings.effect {
        case .static: classic = .static
        case .breathingSingle: classic = .breathing
        case .blinking: classic = .blinking
        case .spectrum: classic = .spectrum
        default: throw RazerError.notSupported("经典灯光不支持\(settings.effect.displayName)")
        }
        requests.append(try StandardProtocol.setLedEffect(device, storage: storage, zone: zone, effect: classic))
        return requests
    }
}
