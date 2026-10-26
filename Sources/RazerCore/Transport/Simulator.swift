import Foundation

/// A fake Razer device for demo mode and tests. It answers the 90-byte protocol like
/// firmware does by convention: a SET command `c` stores its arguments and the matching GET
/// `c | 0x80` returns them. Unknown GETs answer 0x05 (not supported).
public final class SimulatedDevice: @unchecked Sendable {
    public enum Shape: Sendable {
        case feature
        case kraken
        case blackShark
    }

    public let productId: UInt16
    public let name: String
    public let serial: String
    public let shape: Shape
    private let lock = NSLock()
    private var store: [String: [UInt8]] = [:]
    private var pending: [UInt8]?
    private var blackShark: [UInt8: UInt8] = [0x21: 82, 0x2A: 0, 0x19: 6, 0x9E: 1, 0x5C: 10]
    private var blackSharkAnc: (UInt8, UInt8) = (0x01, 2)
    public private(set) var outputLog: [[UInt8]] = []

    public init(productId: UInt16, name: String, serial: String = "PM2610H0SIM0001", shape: Shape = .feature) {
        self.productId = productId
        self.name = name
        self.serial = serial
        self.shape = shape
    }

    /// The demo set shown when no real device is attached.
    public static func demoDevices() -> [SimulatedDevice] {
        [
            SimulatedDevice(productId: 0x00C1, name: "Razer Viper V3 Pro"),
            SimulatedDevice(productId: 0x024E, name: "Razer BlackWidow V3"),
            SimulatedDevice(productId: 0x02D0, name: "Razer Huntsman V3 Pro TKL"),
            SimulatedDevice(productId: 0x0539, name: "Razer Barracuda Pro"),
            SimulatedDevice(productId: 0x030E, name: "Razer Aether Lamp"),
            SimulatedDevice(productId: 0x0510, name: "Razer Kraken 7.1 V2", shape: .kraken),
            SimulatedDevice(productId: 0x101B, name: "Razer BlackShark V3 Pro", shape: .blackShark),
            SimulatedDevice(productId: 0x0567, name: "Razer Kraken V4 Pro", shape: .blackShark),
        ]
    }

    /// HID interfaces that the device would enumerate with.
    public func interfaces(registryBase: UInt64) -> [HIDInterface] {
        switch shape {
        case .feature:
            return [HIDInterface(simulated: self, usagePage: 0x01, usage: 0x02, feature: 90, output: 0, input: 8,
                                 registryId: registryBase)]
        case .kraken:
            return [HIDInterface(simulated: self, usagePage: 0x0C, usage: 0x01, feature: 0, output: 37, input: 37,
                                 registryId: registryBase)]
        case .blackShark:
            // The Kraken V4 Pro carries a HID LampArray on the same interface.
            return [HIDInterface(simulated: self, usagePage: productId == 0x0567 ? 0x0C : 0xFF14, usage: 0x01,
                                 feature: productId == 0x0567 ? 51 : 0, output: 64, input: 64, registryId: registryBase)]
        }
    }

    private func key(_ commandClass: UInt8, _ command: UInt8, _ args: ArraySlice<UInt8>) -> String {
        // Lighting and audio commands are keyed by their storage/zone or profile prefix.
        let prefix: Int
        switch commandClass {
        case 0x03 where command & 0x7F != 0x0A && command & 0x7F != 0x0D: prefix = 2
        case 0x0F where command & 0x7F == 0x04: prefix = 2
        case 0x0F where command & 0x7F == 0x02 && args.first == 0x01: prefix = 2
        case 0x02, 0x08, 0x18: prefix = 1
        default: prefix = 0
        }
        let id = String(format: "%02X%02X", commandClass, command & 0x7F)
        return id + ":" + args.prefix(prefix).hexString
    }

    private func defaultAnswer(_ commandClass: UInt8, _ command: UInt8, _ args: ArraySlice<UInt8>) -> [UInt8]? {
        let a = Array(args)
        switch (commandClass, command) {
        case (0x00, 0x81): return [1, 8]
        case (0x00, 0x87): return [2, 1, 0, 0]
        case (0x00, 0x82): return Array(serial.utf8)
        case (0x01, 0x83): return Array(serial.utf8)
        case (0x00, 0x84): return [0x03, 0x00]
        case (0x00, 0x85): return [0x01]
        case (0x00, 0xC0): return [0x00, 0x08]
        case (0x00, 0x8E): return [0x00, 0x08]
        case (0x00, 0x88): return [0, 0, 0]
        case (0x04, 0x85): return [a.first ?? 0, 0x06, 0x40, 0x06, 0x40]
        case (0x04, 0x86):
            return [0x01, 2, 3, 0, 0x03, 0x20, 0x03, 0x20, 0, 0, 1, 0x06, 0x40, 0x06, 0x40, 0, 0, 2, 0x0C, 0x80, 0x0C, 0x80, 0, 0]
        case (0x07, 0x80): return [0xC8, 0xC8]  // OpenRazer reads byte 1, protocol 25 byte 0
        case (0x07, 0x84): return [0x00, 0x00]
        case (0x07, 0x83): return [0x01, 0x2C]
        case (0x07, 0x81): return [0x26]
        case (0x07, 0x82): return [0xB4]
        case (0x0F, 0x84), (0x03, 0x83): return [a[0], a[1], 0xB4]
        case (0x0E, 0x84): return [0x01, 0xB4]
        case (0x02, 0x94): return [0x01, 0x00]
        case (0x02, 0x96), (0x02, 0x97): return [0x01, 0x01]
        case (0x02, 0x82): return [0x00, 0x14, 0x00, 0x28]
        case (0x10, 0x83): return [ChromaEffect.static.rawValue, 0, 0, 1, 0x44, 0xD6, 0x2C]
        case (0x10, 0x85): return [0xB4]
        case (0x0F, 0x82): return [1, 0, ChromaEffect.spectrum.rawValue, 0, 0, 0]
        case (0x08, 0x82): return [0x00, 0x02]
        case (0x08, 0x84): return [0x00] + [UInt8](repeating: 50, count: 10)
        case (0x08, 0x87): return [0x00, 30]
        case (0x08, 0x88): return [0x00, 0x00]
        case (0x08, 0x97): return [0x00, 70]
        case (0x08, 0x8A): return [0x00, AudioSource.usb.rawValue]
        case (0x08, 0x9C): return [0x00, 0x01]
        case (0x18, 0x86): return [0x00, AncState.on.rawValue, 5]
        default: return nil
        }
    }

    func answer(_ request: [UInt8]) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard let report = try? RazerReport(bytes: request) else { return request }
        var response = request
        let commandClass = report.commandClass
        let command = report.commandId
        let args = report.rawArguments
        if command & 0x80 == 0 {
            // SET: remember the payload for the matching GET.
            var stored = Array(report.arguments)
            if commandClass == 0x00 && command == 0x0E { stored = [0x00] + stored }
            store[key(commandClass, command, args)] = stored
            response[0] = 0x02
        } else if let value = store[key(commandClass, command, args)] ?? defaultAnswer(commandClass, command, args) {
            response[0] = 0x02
            let count = min(value.count, 80)
            for index in 0..<80 { response[8 + index] = index < count ? value[index] : 0 }
        } else {
            response[0] = 0x05
        }
        response[88] = RazerReport.crc(response)
        return response
    }

    /// HID LampArray: a 9-lamp headset that accepts every update.
    func featureReport(_ reportId: UInt8) -> [UInt8] {
        guard reportId == 0x31 else { return [reportId] }
        return [0x31, 0x09, 0x00, 0x4C, 0x81, 0, 0, 0xB8, 0x88, 0, 0, 0, 0, 0, 0, 0x0B, 0, 0, 0, 0x20, 0x4E, 0, 0]
    }

    func handleFeature(_ report: [UInt8]) {
        lock.lock()
        outputLog.append(report)
        lock.unlock()
    }

    /// Kraken output reports have no reply; BlackShark output reports answer on report 0x02.
    func handleOutput(_ report: [UInt8]) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        outputLog.append(report)
        guard shape == .blackShark, report.count >= 64 else { return nil }
        let commandClass = report[10]
        var arguments: [UInt8] = []
        switch commandClass {
        case 0x99: blackShark[0x19] = report[13]
        case 0x9E where report[12] == 0x01: blackShark[0x9E] = report[13]
        case 0x92: blackSharkAnc = (report[13], report[14])
        case 0xDC: blackShark[0x5C] = report[13]
        case 0x12: arguments = [blackSharkAnc.0, blackSharkAnc.1]
        default:
            if let value = blackShark[commandClass] { arguments = [value] }
        }
        guard !arguments.isEmpty else { return nil }
        var reply = [UInt8](repeating: 0, count: 64)
        reply[0] = 0x02
        reply[1] = 0x02
        reply[10] = commandClass
        reply[11] = 0x01
        reply[12] = UInt8(arguments.count)
        reply.replaceSubrange(13..<(13 + arguments.count), with: arguments)
        reply[62] = BlackSharkProtocol.crc(reply)
        return reply
    }
}

final class SimulatedFeatureIO: RawFeatureIO {
    let device: SimulatedDevice
    private var last: [UInt8]?
    var label: String { "模拟设备" }

    init(device: SimulatedDevice) {
        self.device = device
    }

    func setFeature(_ bytes: [UInt8]) throws {
        last = device.answer(bytes)
    }

    func getFeature(length: Int) throws -> [UInt8] {
        guard let last else { throw RazerError.transport("没有待读取的响应") }
        return last
    }
}
