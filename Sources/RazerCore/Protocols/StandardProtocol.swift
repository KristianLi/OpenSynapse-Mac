import Foundation

public struct RazerColor: Equatable, Hashable, Sendable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = RazerColor(0, 0, 0)
    public static let razerGreen = RazerColor(0x44, 0xD6, 0x2C)

    var bytes: [UInt8] { [red, green, blue] }
}

public enum ClassicLedEffect: UInt8, Sendable {
    case `static` = 0x00
    case blinking = 0x01
    case breathing = 0x02
    case spectrum = 0x04
}

/// `razer_chroma_standard_*` builders from OpenRazer's razerchromacommon.c.
enum StandardProtocol {
    static let noStore: UInt8 = 0x00
    static let variableStore: UInt8 = 0x01
    static let normalDeviceMode: UInt8 = 0x00
    static let driverDeviceMode: UInt8 = 0x03

    static func create(
        _ device: DeviceDefinition,
        _ builder: String,
        dataSize: UInt8,
        commandClass: UInt8,
        commandId: UInt8,
        arguments: [UInt8] = [],
        allowArgumentsBeyondDeclaredSize: Bool = false
    ) throws -> RazerRequest {
        let transaction = try device.requiredTransaction(builder)
        let report = try RazerReport(
            transactionId: transaction,
            dataSize: dataSize,
            commandClass: commandClass,
            commandId: commandId,
            arguments: arguments,
            allowArgumentsBeyondDeclaredSize: allowArgumentsBeyondDeclaredSize)
        return RazerRequest(builder: builder, report: report)
    }

    static func getFirmware(_ device: DeviceDefinition) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_firmware_version", dataSize: 0x02, commandClass: 0x00, commandId: 0x81)
    }

    static func getSerial(_ device: DeviceDefinition) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_serial", dataSize: 0x16, commandClass: 0x00, commandId: 0x82)
    }

    static func getDeviceMode(_ device: DeviceDefinition) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_device_mode", dataSize: 0x02, commandClass: 0x00, commandId: 0x84)
    }

    /// OpenRazer writes driver mode 0x03 to every wireless mouse it drives; a wireless mouse
    /// left in normal mode never joins the 2.4 GHz link.
    static func setDriverDeviceMode(_ device: DeviceDefinition) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_device_mode", dataSize: 0x02, commandClass: 0x00, commandId: 0x04,
                   arguments: [driverDeviceMode, noStore])
    }

    static func getLedState(_ device: DeviceDefinition, storage: UInt8, zone: UInt8) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_led_state", dataSize: 0x03, commandClass: 0x03, commandId: 0x80,
                   arguments: [storage, zone])
    }

    static func setLedState(_ device: DeviceDefinition, storage: UInt8, zone: UInt8, enabled: Bool) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_led_state", dataSize: 0x03, commandClass: 0x03, commandId: 0x00,
                   arguments: [storage, zone, enabled ? 1 : 0])
    }

    static func getLedEffect(_ device: DeviceDefinition, storage: UInt8, zone: UInt8) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_led_effect", dataSize: 0x03, commandClass: 0x03, commandId: 0x82,
                   arguments: [storage, zone])
    }

    static func setLedEffect(_ device: DeviceDefinition, storage: UInt8, zone: UInt8, effect: ClassicLedEffect) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_led_effect", dataSize: 0x03, commandClass: 0x03, commandId: 0x02,
                   arguments: [storage, zone, effect.rawValue])
    }

    static func setLedColor(_ device: DeviceDefinition, storage: UInt8, zone: UInt8, color: RazerColor) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_led_rgb", dataSize: 0x05, commandClass: 0x03, commandId: 0x01,
                   arguments: [storage, zone] + color.bytes)
    }

    static func setLedBlinking(_ device: DeviceDefinition, storage: UInt8, zone: UInt8) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_led_blinking", dataSize: 0x04, commandClass: 0x03, commandId: 0x04,
                   arguments: [storage, zone, 0x05, 0x05])
    }

    static func getLedBrightness(_ device: DeviceDefinition, storage: UInt8, zone: UInt8) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_get_led_brightness", dataSize: 0x03, commandClass: 0x03, commandId: 0x83,
                   arguments: [storage, zone])
    }

    static func setLedBrightness(_ device: DeviceDefinition, storage: UInt8, zone: UInt8, brightness: UInt8) throws -> RazerRequest {
        try create(device, "razer_chroma_standard_set_led_brightness", dataSize: 0x03, commandClass: 0x03, commandId: 0x03,
                   arguments: [storage, zone, brightness])
    }

    static func parseFirmware(_ response: RazerReport) throws -> String {
        let args = Array(try response.successfulArguments(minimumLength: 2))
        return "\(args[0]).\(args[1])"
    }

    static func parseSerial(_ response: RazerReport) throws -> String {
        let args = Array(try response.successfulArguments(minimumLength: 1))
        let end = args.firstIndex(of: 0) ?? args.count
        return String(decoding: args[..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseDeviceMode(_ response: RazerReport) throws -> UInt8 {
        try response.successfulArguments(minimumLength: 2).first!
    }

    static func parseLedState(_ response: RazerReport, storage: UInt8, zone: UInt8) throws -> Bool {
        let args = try ledArguments(response, minimumLength: 3, storage: storage, zone: zone)
        switch args[2] {
        case 0: return false
        case 1: return true
        default: throw RazerError.invalidResponse("无效的灯光开关状态")
        }
    }

    static func ledArguments(_ response: RazerReport, minimumLength: Int, storage: UInt8, zone: UInt8) throws -> [UInt8] {
        let args = Array(try response.successfulArguments(minimumLength: minimumLength))
        guard args[0] == storage, args[1] == zone else {
            throw RazerError.invalidResponse("灯光响应与请求的存储区或灯区不匹配")
        }
        return args
    }
}
