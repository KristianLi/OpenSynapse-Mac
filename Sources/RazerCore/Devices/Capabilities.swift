import Foundation

public enum Capability: String, CaseIterable, Sendable {
    case firmwareRead, serialRead, deviceModeWrite
    case batteryRead, chargingRead
    case pollingRateRead, pollingRateWrite
    case dpiRead, dpiWrite, dpiStagesRead, dpiStagesWrite
    case idleTimeoutRead, idleTimeoutWrite
    case lowBatteryThresholdRead, lowBatteryThresholdWrite
    case brightnessRead, brightnessWrite
    case ledStateRead, ledStateWrite, ledEffectRead, ledEffectWrite, ledColorWrite, ledBlinkingWrite
    case lightingEffectWrite, matrixFrameWrite, reactiveTriggerWrite
    case scrollModeRead, scrollModeWrite, scrollAccelerationRead, scrollAccelerationWrite, smartReelRead, smartReelWrite
    case fnPrimaryWrite, keyswitchOptimizationRead, keyswitchOptimizationWrite
    case hyperPollingIndicatorWrite, hyperPollingPairWrite, hyperPollingUnpairWrite
}

public struct LightingZoneCapabilities: Equatable, Sendable {
    public let zone: LedZone
    public let canReadBrightness: Bool
    public let canWriteBrightness: Bool
    public let canReadState: Bool
    public let canWriteState: Bool
    public let canReadEffect: Bool
    public let canWriteEffect: Bool
    public let canWriteColor: Bool
    public let canWriteBlinking: Bool
    public let effects: Set<LightingEffect>

    /// Effects in a stable display order.
    public var orderedEffects: [LightingEffect] { LightingEffect.allCases.filter(effects.contains) }
}

/// Turns catalog facts into the set of controls a device page may show. A capability is
/// published only when both the OpenRazer source declares it and a transaction resolves it.
public enum CapabilityResolver {
    private static let sourceZones: [(name: String, zone: LedZone)] = [
        ("logo", .logo), ("scroll", .scrollWheel), ("backlight", .backlight), ("left", .leftSide),
        ("right", .rightSide), ("charging", .charging), ("fast_charging", .fastCharging), ("fully_charged", .fullyCharged),
    ]

    public static func capabilities(_ device: DeviceDefinition) -> Set<Capability> {
        var result = Set<Capability>()
        let zones = lightingZones(device).values
        func has(_ builder: String) -> Bool { device.hasBuilder(builder) }
        func add(_ capability: Capability, _ source: String, _ builder: String) {
            if device.has(source), has(builder) { result.insert(capability) }
        }
        func addAnyDeclared(_ capability: Capability, _ source: String, _ builders: String...) {
            if device.has(source), builders.contains(where: has) { result.insert(capability) }
        }
        func addAnySource(_ capability: Capability, _ sources: [String], _ builders: String...) {
            if sources.contains(where: device.has), builders.contains(where: has) { result.insert(capability) }
        }
        func addAnyBuilder(_ capability: Capability, _ builders: String...) {
            if builders.contains(where: has) { result.insert(capability) }
        }

        // The firmware GET is the side-effect-free endpoint probe for every catalog entry, so it is
        // shown whenever its transaction resolves, even if the source capability set omits it.
        addAnyBuilder(.firmwareRead, "razer_chroma_standard_get_firmware_version")
        if device.transactions["razer_chroma_standard_get_serial"] != nil {
            result.insert(.serialRead)
        }
        addAnyBuilder(.deviceModeWrite, "razer_chroma_standard_set_device_mode")
        add(.batteryRead, "get_battery", "razer_chroma_misc_get_battery_level")
        add(.chargingRead, "is_charging", "razer_chroma_misc_get_charging_status")
        addAnyDeclared(.pollingRateRead, "get_poll_rate", "razer_chroma_misc_get_polling_rate", "razer_chroma_misc_get_polling_rate2")
        addAnyDeclared(.pollingRateWrite, "set_poll_rate", "razer_chroma_misc_set_polling_rate", "razer_chroma_misc_set_polling_rate2")
        addAnySource(.dpiRead, ["get_dpi_xy", "get_dpi_xy_byte"], "razer_chroma_misc_get_dpi_xy", "razer_chroma_misc_get_dpi_xy_byte")
        addAnySource(.dpiWrite, ["set_dpi_xy", "set_dpi_xy_byte"], "razer_chroma_misc_set_dpi_xy", "razer_chroma_misc_set_dpi_xy_byte")
        add(.dpiStagesRead, "get_dpi_stages", "razer_chroma_misc_get_dpi_stages")
        add(.dpiStagesWrite, "set_dpi_stages", "razer_chroma_misc_set_dpi_stages")
        add(.idleTimeoutRead, "get_idle_time", "razer_chroma_misc_get_idle_time")
        add(.idleTimeoutWrite, "set_idle_time", "razer_chroma_misc_set_idle_time")
        add(.lowBatteryThresholdRead, "get_low_battery_threshold", "razer_chroma_misc_get_low_battery_threshold")
        add(.lowBatteryThresholdWrite, "set_low_battery_threshold", "razer_chroma_misc_set_low_battery_threshold")
        if zones.contains(where: \.canReadBrightness) { result.insert(.brightnessRead) }
        if zones.contains(where: \.canWriteBrightness) { result.insert(.brightnessWrite) }
        if zones.contains(where: \.canReadState) { result.insert(.ledStateRead) }
        if zones.contains(where: \.canWriteState) { result.insert(.ledStateWrite) }
        if zones.contains(where: \.canReadEffect) { result.insert(.ledEffectRead) }
        if zones.contains(where: \.canWriteEffect) { result.insert(.ledEffectWrite) }
        if zones.contains(where: \.canWriteColor) { result.insert(.ledColorWrite) }
        if zones.contains(where: \.canWriteBlinking) { result.insert(.ledBlinkingWrite) }
        if zones.contains(where: { !$0.effects.isEmpty }) { result.insert(.lightingEffectWrite) }
        if device.matrixDimensions != nil, device.has("set_key_row") {
            addAnyBuilder(.matrixFrameWrite, "razer_chroma_standard_matrix_set_custom_frame",
                          "razer_chroma_extended_matrix_set_custom_frame", "razer_chroma_extended_matrix_set_custom_frame2")
        }
        add(.reactiveTriggerWrite, "trigger_reactive_effect", "razer_chroma_misc_matrix_reactive_trigger")
        add(.scrollModeRead, "get_scroll_mode", "razer_chroma_misc_get_scroll_mode")
        add(.scrollModeWrite, "set_scroll_mode", "razer_chroma_misc_set_scroll_mode")
        add(.scrollAccelerationRead, "get_scroll_acceleration", "razer_chroma_misc_get_scroll_acceleration")
        add(.scrollAccelerationWrite, "set_scroll_acceleration", "razer_chroma_misc_set_scroll_acceleration")
        add(.smartReelRead, "get_scroll_smart_reel", "razer_chroma_misc_get_scroll_smart_reel")
        add(.smartReelWrite, "set_scroll_smart_reel", "razer_chroma_misc_set_scroll_smart_reel")
        add(.keyswitchOptimizationRead, "get_keyswitch_optimization", "razer_chroma_misc_get_keyswitch_optimization")
        if device.has("set_keyswitch_optimization"),
           has("razer_chroma_misc_set_keyswitch_optimization_command1"),
           has("razer_chroma_misc_set_keyswitch_optimization_command2") {
            result.insert(.keyswitchOptimizationWrite)
        }
        add(.hyperPollingIndicatorWrite, "set_hyperpolling_wireless_dongle_indicator_led_mode",
            "razer_chroma_misc_set_hyperpolling_wireless_dongle_indicator_led_mode")
        if device.has("set_hyperpolling_wireless_dongle_pair"),
           has("razer_chroma_misc_set_hyperpolling_wireless_dongle_pair_step1"),
           has("razer_chroma_misc_set_hyperpolling_wireless_dongle_pair_step2") {
            result.insert(.hyperPollingPairWrite)
        }
        add(.hyperPollingUnpairWrite, "set_hyperpolling_wireless_dongle_unpair",
            "razer_chroma_misc_set_hyperpolling_wireless_dongle_unpair")
        return result
    }

    public static func lightingZones(_ device: DeviceDefinition) -> [LedZone: LightingZoneCapabilities] {
        var zones: Set<LedZone> = [device.defaultLedZone]
        for (builder, prefixes) in device.builderArgumentPrefixes
        where builder.contains("matrix_effect") || builder.contains("brightness") || builder.contains("_led_") {
            for prefix in prefixes where prefix.count >= 2 {
                if let zone = LedZone(rawValue: prefix[1]) {
                    zones.insert(zone)
                }
            }
        }
        for capability in device.sourceCapabilities {
            if let zone = sourceZone(capability) {
                zones.insert(zone)
            }
        }

        let effectsByZone = lightingEffectsByZone(device)
        var output: [LedZone: LightingZoneCapabilities] = [:]
        for zone in zones.sorted() {
            let effects = effectsByZone[zone] ?? []
            let canReadBrightness = hasSourceBrightness(device, zone, write: false)
                && (try? LightingProtocol.getBrightness(device, storage: device.defaultStorage, zone: zone)) != nil
            let canWriteBrightness = hasSourceBrightness(device, zone, write: true)
                && (try? LightingProtocol.setBrightness(device, storage: device.defaultStorage, zone: zone, brightness: 0)) != nil
            let canReadState = device.has("get_logo_active") && zone == .logo
                && canUseClassicBuilder(device, "razer_chroma_standard_get_led_state", zone)
            let canWriteState = device.transactions["razer_chroma_standard_set_led_state"] != nil
                && hasSourceStateWrite(device, zone)
                && supportsStorageAndZone(device, "razer_chroma_standard_set_led_state", device.defaultStorage, zone)
            let canReadEffect = zone == .macro && device.has("get_macro_effect")
                && canUseClassicBuilder(device, "razer_chroma_standard_get_led_effect", zone)
            let canWriteEffect = !effects.isEmpty && canUseClassicBuilder(device, "razer_chroma_standard_set_led_effect", zone)
            let canWriteColor = effects.contains(where: { [.static, .breathingSingle, .blinking].contains($0) })
                && canUseClassicBuilder(device, "razer_chroma_standard_set_led_rgb", zone)
            let canWriteBlinking = effects.contains(.blinking)
                && canUseClassicBuilder(device, "razer_chroma_standard_set_led_blinking", zone)
            if canReadBrightness || canWriteBrightness || canReadState || canWriteState || canReadEffect
                || canWriteEffect || canWriteColor || canWriteBlinking || !effects.isEmpty {
                output[zone] = LightingZoneCapabilities(
                    zone: zone, canReadBrightness: canReadBrightness, canWriteBrightness: canWriteBrightness,
                    canReadState: canReadState, canWriteState: canWriteState, canReadEffect: canReadEffect,
                    canWriteEffect: canWriteEffect, canWriteColor: canWriteColor, canWriteBlinking: canWriteBlinking,
                    effects: effects)
            }
        }
        return output
    }

    private static func lightingEffectsByZone(_ device: DeviceDefinition) -> [LedZone: Set<LightingEffect>] {
        var effects: [LedZone: Set<LightingEffect>] = [:]
        for effect in LightingEffect.allCases {
            if let zone = try? LightingProtocol.resolveEffectZone(device, effect) {
                effects[zone, default: []].insert(effect)
            }
        }
        for capability in device.sourceCapabilities {
            guard let zone = sourceZone(capability), let effect = sourceEffect(capability),
                  (try? LightingProtocol.createEffectRequests(device, LightingSettings(effect: effect, zone: zone))) != nil
            else {
                continue
            }
            effects[zone, default: []].insert(effect)
        }
        return effects
    }

    private static func sourceEffect(_ capability: String) -> LightingEffect? {
        for source in sourceZones {
            let prefix = "set_\(source.name)_"
            guard capability.hasPrefix(prefix) else { continue }
            switch String(capability.dropFirst(prefix.count)) {
            case "none": return .off
            case "static": return .static
            case "spectrum": return .spectrum
            case "wave": return .wave
            case "reactive": return .reactive
            case "breath_random": return .breathingRandom
            case "breath_mono", "breath_single": return .breathingSingle
            case "breath_dual": return .breathingDual
            default: continue
            }
        }
        return nil
    }

    private static func sourceZone(_ capability: String) -> LedZone? {
        sourceZones.first { capability.hasPrefix("get_\($0.name)_") || capability.hasPrefix("set_\($0.name)_") }?.zone
    }

    private static func hasSourceStateWrite(_ device: DeviceDefinition, _ zone: LedZone) -> Bool {
        guard let name = sourceZones.first(where: { $0.zone == zone })?.name else { return false }
        return device.has("set_\(name)_active") || device.has("set_\(name)_on")
    }

    private static func hasSourceBrightness(_ device: DeviceDefinition, _ zone: LedZone, write: Bool) -> Bool {
        let operation = write ? "set" : "get"
        if zone == device.defaultLedZone, device.has("\(operation)_brightness") {
            return true
        }
        guard let name = sourceZones.first(where: { $0.zone == zone })?.name else { return false }
        return device.has("\(operation)_\(name)_brightness")
    }

    static func supportsStorageAndZone(_ device: DeviceDefinition, _ builder: String, _ storage: Storage, _ zone: LedZone) -> Bool {
        (device.builderArgumentPrefixes[builder] ?? []).contains { prefix in
            (prefix.count >= 2 && prefix[0] == storage.rawValue && prefix[1] == zone.rawValue)
                || (prefix.count == 1 && prefix[0] == storage.rawValue)
        }
    }

    private static func canUseClassicBuilder(_ device: DeviceDefinition, _ builder: String, _ zone: LedZone) -> Bool {
        device.transactions[builder] != nil
            && (device.builderArgumentPrefixes[builder] ?? []).contains { $0.count == 1 || ($0.count >= 2 && $0[1] == zone.rawValue) }
    }
}
