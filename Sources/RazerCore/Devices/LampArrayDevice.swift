import Foundation

/// HID LampArray (Lighting and Illumination page 0x59), the standard behind Windows Dynamic
/// Lighting. Newer Razer devices such as the Kraken V4 Pro and its control hub expose it next
/// to their vendor channel. Report layouts follow the HID Usage Tables:
///
///     0x31 LampArrayAttributes  LampCount u16, BoundingBox W/H/D u32 (µm), Kind u32, MinUpdateInterval u32 (µs)
///     0x35 LampRangeUpdate      Flags u8, LampIdStart u16, LampIdEnd u16, R, G, B, Intensity
///     0x36 LampArrayControl     AutonomousMode u8
enum LampArrayProtocol {
    static let attributesReport: UInt8 = 0x31
    static let rangeUpdateReport: UInt8 = 0x35
    static let controlReport: UInt8 = 0x36
    static let attributesLength = 23

    struct Attributes: Equatable, Sendable {
        let lampCount: Int
        let kind: Int
        let minUpdateInterval: TimeInterval
    }

    static func parseAttributes(_ bytes: [UInt8]) -> Attributes? {
        guard bytes.count >= attributesLength, bytes[0] == attributesReport else { return nil }
        let count = Int(bytes[1]) | Int(bytes[2]) << 8
        let kind = Int(bytes[15]) | Int(bytes[16]) << 8
        let interval = Int(bytes[19]) | Int(bytes[20]) << 8 | Int(bytes[21]) << 16
        // Kinds 1...11 are defined (keyboard, mouse, … headset); anything else is not a LampArray.
        guard (1...1024).contains(count), (1...11).contains(kind) else { return nil }
        return Attributes(lampCount: count, kind: kind, minUpdateInterval: TimeInterval(interval) / 1_000_000)
    }

    static func autonomous(_ enabled: Bool) -> [UInt8] { [controlReport, enabled ? 1 : 0] }

    static func fill(lampCount: Int, color: RazerColor, intensity: UInt8) -> [UInt8] {
        let last = UInt16(max(lampCount - 1, 0))
        // Flags bit 0 = LampUpdateComplete: apply now instead of buffering.
        return [rangeUpdateReport, 0x01, 0x00, 0x00, last.low, last.high, color.red, color.green, color.blue, intensity]
    }
}

/// Lighting through HID LampArray. The device keeps no readable colour state, so the page
/// only writes; "autonomous mode" hands the lamps back to the firmware's own effect.
public final class LampArrayDevice: @unchecked Sendable {
    public let productId: UInt16
    public let name: String
    public let channel: ReportChannel
    public let lampCount: Int

    init(productId: UInt16, name: String, channel: ReportChannel, attributes: LampArrayProtocol.Attributes) {
        self.productId = productId
        self.name = name
        self.channel = channel
        lampCount = attributes.lampCount
    }

    /// Reads the attributes report; nil when the interface is not a LampArray.
    static func probe(_ channel: ReportChannel) async -> LampArrayProtocol.Attributes? {
        guard let bytes = try? await channel.getFeature(reportId: LampArrayProtocol.attributesReport,
                                                         length: LampArrayProtocol.attributesLength + 8) else { return nil }
        return LampArrayProtocol.parseAttributes(bytes)
    }

    public func setColor(_ color: RazerColor, brightness: UInt8) async throws {
        try await channel.setFeature(LampArrayProtocol.autonomous(false))
        try await channel.setFeature(LampArrayProtocol.fill(lampCount: lampCount, color: color, intensity: brightness))
    }

    public func off() async throws {
        try await setColor(.black, brightness: 0)
    }

    /// Returns the lamps to the effect stored in the device.
    public func restoreDeviceEffect() async throws {
        try await channel.setFeature(LampArrayProtocol.autonomous(true))
    }
}
