import Foundation

/// The 90-byte Razer feature report shared by OpenRazer devices and the protocol 25 families.
///
/// macOS sends report ID 0 as a separate argument, so the payload is the OpenRazer logical
/// layout (Windows prepends a zero byte and uses 91 bytes; every index here is one lower):
///
///     0 status, 1 transaction id, 2-3 remaining packets, 4 protocol type,
///     5 data size, 6 command class, 7 command id, 8..87 arguments, 88 CRC, 89 reserved
///
/// The CRC is the XOR of bytes 2..87.
public struct RazerReport: Equatable, Sendable, CustomStringConvertible {
    public static let length = 90
    public static let argumentsOffset = 8
    public static let maximumArguments = 80

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.length else {
            throw RazerError.invalidResponse("报告长度应为 \(Self.length) 字节，实际 \(bytes.count) 字节")
        }
        self.bytes = bytes
    }

    /// Builds a request. `arguments` may exceed `dataSize` only when the caller opts in, which
    /// upstream needs for a few builders that send more payload than they declare.
    public init(
        transactionId: UInt8,
        dataSize: UInt8,
        commandClass: UInt8,
        commandId: UInt8,
        arguments: [UInt8] = [],
        allowArgumentsBeyondDeclaredSize: Bool = false
    ) throws {
        guard dataSize <= 80, arguments.count <= 80,
              allowArgumentsBeyondDeclaredSize || arguments.count <= Int(dataSize)
        else {
            throw RazerError.invalidArgument("数据长度超出范围（size=\(dataSize), args=\(arguments.count)）")
        }
        var report = [UInt8](repeating: 0, count: Self.length)
        report[1] = transactionId
        report[5] = dataSize
        report[6] = commandClass
        report[7] = commandId
        report.replaceSubrange(Self.argumentsOffset..<(Self.argumentsOffset + arguments.count), with: arguments)
        report[88] = Self.crc(report)
        bytes = report
    }

    public var status: UInt8 { bytes[0] }
    public var transactionId: UInt8 {
        get { bytes[1] }
        set {
            bytes[1] = newValue
            bytes[88] = Self.crc(bytes)
        }
    }
    public var dataSize: UInt8 { bytes[5] }
    public var commandClass: UInt8 { bytes[6] }
    public var commandId: UInt8 { bytes[7] }
    public var crc: UInt8 { bytes[88] }

    /// The declared argument bytes.
    public var arguments: ArraySlice<UInt8> {
        bytes[Self.argumentsOffset..<(Self.argumentsOffset + Int(min(dataSize, 80)))]
    }

    /// The whole 80-byte argument area. Some firmware answers beyond the declared size.
    public var rawArguments: ArraySlice<UInt8> {
        bytes[Self.argumentsOffset..<(Self.argumentsOffset + Self.maximumArguments)]
    }

    public static func crc(_ report: [UInt8]) -> UInt8 {
        var value: UInt8 = 0
        for index in 2...87 {
            value ^= report[index]
        }
        return value
    }

    public var hasValidCrc: Bool { bytes[88] == Self.crc(bytes) }

    /// Matches a response to its request the way upstream does: same transaction, class,
    /// command and remaining-packet count, plus a valid CRC.
    public func matches(response: RazerReport, allowRemainingPacketsMismatch: Bool = false) -> Bool {
        response.bytes[1] == bytes[1]
            && (allowRemainingPacketsMismatch || (response.bytes[2] == bytes[2] && response.bytes[3] == bytes[3]))
            && response.bytes[6] == bytes[6]
            && response.bytes[7] == bytes[7]
            && response.hasValidCrc
    }

    public static func isAcceptedStatus(_ status: UInt8) -> Bool { status == 0x01 || status == 0x02 }

    /// Validated declared arguments of a successful response.
    public func successfulArguments(minimumLength: Int) throws -> ArraySlice<UInt8> {
        guard Self.isAcceptedStatus(status), Int(dataSize) >= minimumLength, dataSize <= 80, hasValidCrc else {
            throw RazerError.invalidResponse("设备响应无效或未成功（status=0x\(String(format: "%02X", status))）")
        }
        return arguments
    }

    /// Validated whole argument area of a successful response.
    public func successfulRawArguments() throws -> ArraySlice<UInt8> {
        guard Self.isAcceptedStatus(status), dataSize <= 80, hasValidCrc else {
            throw RazerError.invalidResponse("设备响应无效或未成功（status=0x\(String(format: "%02X", status))）")
        }
        return rawArguments
    }

    public var description: String {
        let args = bytes[Self.argumentsOffset..<(Self.argumentsOffset + Int(min(dataSize, 16)))]
        return String(
            format: "txn=%02X size=%d class=%02X cmd=%02X args=%@",
            bytes[1], bytes[5], bytes[6], bytes[7], args.hexString)
    }
}

/// A request plus the catalog builder name it came from, for diagnostics and tests.
public struct RazerRequest: Sendable {
    public let builder: String
    public var report: RazerReport

    public init(builder: String, report: RazerReport) {
        self.builder = builder
        self.report = report
    }
}

public enum RazerError: Error, LocalizedError, Equatable {
    case notSupported(String)
    case rejected(String)
    case timeout(String)
    case transport(String)
    case invalidResponse(String)
    case invalidArgument(String)
    case notReady(String)
    case permissionDenied(String)

    public var errorDescription: String? {
        switch self {
        case .notSupported(let message): "不支持：\(message)"
        case .rejected(let message): "设备拒绝：\(message)"
        case .timeout(let message): "无响应：\(message)"
        case .transport(let message): "通信失败：\(message)"
        case .invalidResponse(let message): "响应无效：\(message)"
        case .invalidArgument(let message): "参数无效：\(message)"
        case .notReady(let message): "设备未就绪：\(message)"
        case .permissionDenied(let message): "没有权限：\(message)"
        }
    }

    /// Errors that mean "this firmware does not offer this control" rather than a dead link.
    public var meansUnsupported: Bool {
        switch self {
        case .notSupported, .rejected, .timeout, .invalidResponse: true
        default: false
        }
    }
}

extension Collection where Element == UInt8 {
    public var hexString: String { map { String(format: "%02X", $0) }.joined() }
}

extension UInt16 {
    var high: UInt8 { UInt8(self >> 8) }
    var low: UInt8 { UInt8(self & 0xFF) }
}

extension Int {
    var highByte: UInt8 { UInt8(truncatingIfNeeded: self >> 8) }
    var lowByte: UInt8 { UInt8(truncatingIfNeeded: self & 0xFF) }
}
