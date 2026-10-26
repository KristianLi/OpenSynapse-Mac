import Foundation
import IOKit
import IOKit.hid
import RazerUSB

public enum TransportPreference: String, CaseIterable, Sendable, Identifiable {
    case automatic, hid, usbControl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动（HID 优先，失败时改用 USB 控制传输）"
        case .hid: "仅 HID 特性报告"
        case .usbControl: "仅 USB 控制传输"
        }
    }
}

/// Raw report I/O for one interface. Implementations block; callers serialize them.
protocol RawFeatureIO: AnyObject {
    var label: String { get }
    func setFeature(_ bytes: [UInt8]) throws
    func getFeature(length: Int) throws -> [UInt8]
}

private func describe(_ result: IOReturn) -> String {
    switch result {
    case kIOReturnNotPermitted: "kIOReturnNotPermitted（未获得权限）"
    case kIOReturnExclusiveAccess: "kIOReturnExclusiveAccess（被其他程序独占）"
    case kIOReturnNotResponding: "kIOReturnNotResponding（设备无响应）"
    case kIOReturnNoDevice: "kIOReturnNoDevice（设备已断开）"
    case kIOReturnUnsupported: "kIOReturnUnsupported（不支持）"
    case kIOReturnTimeout: "kIOReturnTimeout（超时）"
    case kIOReturnAborted: "kIOReturnAborted（已中止）"
    default: String(format: "IOReturn 0x%08X", UInt32(bitPattern: result))
    }
}

final class HIDFeatureIO: RawFeatureIO {
    let interface: HIDInterface
    private var opened = false
    var label: String { "HID" }

    init(interface: HIDInterface) {
        self.interface = interface
    }

    deinit {
        if opened, let device = interface.device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func ensureOpen() throws {
        guard !opened else { return }
        guard let device = interface.device else { throw RazerError.transport("没有 HID 设备句柄") }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted {
                throw RazerError.permissionDenied("打开 HID 接口需要“输入监控”权限：\(describe(result))")
            }
            throw RazerError.transport("无法打开 HID 接口：\(describe(result))")
        }
        opened = true
    }

    func setFeature(_ bytes: [UInt8]) throws {
        try ensureOpen()
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(interface.device!, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            throw RazerError.transport("SET_REPORT 失败：\(describe(result))")
        }
    }

    func getFeature(length: Int) throws -> [UInt8] {
        try ensureOpen()
        var buffer = [UInt8](repeating: 0, count: length)
        var size = CFIndex(length)
        let result = buffer.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(interface.device!, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &size)
        }
        guard result == kIOReturnSuccess else {
            throw RazerError.transport("GET_REPORT 失败：\(describe(result))")
        }
        return size >= length ? buffer : Array(buffer.prefix(Int(size)))
    }
}

/// OpenRazer's own path: HID class SET_REPORT/GET_REPORT on the default control pipe,
/// addressed to the control interface. It does not open the HID interface.
final class USBControlFeatureIO: RawFeatureIO {
    let interface: HIDInterface
    let interfaceIndex: UInt16
    var label: String { "USB 控制传输 (wIndex=\(interfaceIndex))" }

    init(interface: HIDInterface, interfaceIndex: UInt16) {
        self.interface = interface
        self.interfaceIndex = interfaceIndex
    }

    func setFeature(_ bytes: [UInt8]) throws {
        var data = bytes
        var transferred: UInt32 = 0
        let result = data.withUnsafeMutableBufferPointer {
            rz_usb_control_request(interface.vendorId, interface.productId, interface.locationId,
                                   0x21, 0x09, 0x0300, interfaceIndex, $0.baseAddress, UInt16($0.count), &transferred)
        }
        guard result == kIOReturnSuccess else {
            throw RazerError.transport("USB SET_REPORT 失败：\(describe(result))")
        }
    }

    func getFeature(length: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        var transferred: UInt32 = 0
        let result = buffer.withUnsafeMutableBufferPointer {
            rz_usb_control_request(interface.vendorId, interface.productId, interface.locationId,
                                   0xA1, 0x01, 0x0300, interfaceIndex, $0.baseAddress, UInt16($0.count), &transferred)
        }
        guard result == kIOReturnSuccess else {
            throw RazerError.transport("USB GET_REPORT 失败：\(describe(result))")
        }
        return buffer
    }
}

/// A Razer 90-byte feature-report endpoint with OpenSynapse's retry and validation rules.
public final class FeatureEndpoint: @unchecked Sendable {
    public let interface: HIDInterface
    public let tag: String
    private let queue: DispatchQueue
    private var primary: RawFeatureIO
    private var fallback: RawFeatureIO?
    private var transaction: UInt8 = 0x1F

    public init(interface: HIDInterface, preference: TransportPreference, tag: String) {
        self.interface = interface
        self.tag = tag
        queue = Self.sharedQueue(for: interface.registryId)
        if let simulated = interface.simulated {
            primary = SimulatedFeatureIO(device: simulated)
            return
        }
        let usb = interface.interfaceNumber.map { USBControlFeatureIO(interface: interface, interfaceIndex: UInt16($0)) }
        switch preference {
        case .usbControl where usb != nil:
            primary = usb!
        case .hid, .usbControl:
            primary = HIDFeatureIO(interface: interface)
        case .automatic:
            primary = HIDFeatureIO(interface: interface)
            fallback = usb
        }
    }

    private let stateLock = NSLock()

    private static let queuesLock = NSLock()
    nonisolated(unsafe) private static var queues: [UInt64: DispatchQueue] = [:]

    /// One serial queue per HID interface for the whole process. A Razer endpoint holds a single
    /// pending response, so two endpoints talking to the same interface (a rescan racing a
    /// battery refresh) would read each other's answers.
    private static func sharedQueue(for registryId: UInt64) -> DispatchQueue {
        queuesLock.lock()
        defer { queuesLock.unlock() }
        if let queue = queues[registryId] { return queue }
        let queue = DispatchQueue(label: "OpenSynapseMac.endpoint.\(registryId)")
        queues[registryId] = queue
        return queue
    }

    /// The path currently used, for the device information panel.
    public var pathDescription: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return primary.label
    }

    /// Protocol 25 services cycle the transaction id 0...0x1F per request.
    public func nextTransactionId() -> UInt8 {
        stateLock.lock()
        defer { stateLock.unlock() }
        transaction = transaction >= 0x1F ? 0 : transaction + 1
        return transaction
    }

    public func query(
        _ request: RazerReport,
        wait: TimeInterval,
        label: String,
        allowRemainingPacketsMismatch: Bool = false
    ) async throws -> RazerReport {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.performQuery(
                        request, wait: wait, label: label, allowRemainingPacketsMismatch: allowRemainingPacketsMismatch))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sends reports without reading responses (matrix frames).
    public func sendBatch(_ requests: [RazerReport], rowDelay: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    for request in requests {
                        try self.withFallback { try $0.setFeature(request.bytes) }
                        if rowDelay > 0 { Thread.sleep(forTimeInterval: rowDelay) }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withFallback<T>(_ body: (RawFeatureIO) throws -> T) throws -> T {
        do {
            return try body(primary)
        } catch let error as RazerError {
            guard let fallback else { throw error }
            DiagnosticLog.shared.write(tag, "\(primary.label) 失败（\(error.localizedDescription)），改用 \(fallback.label)")
            stateLock.lock()
            primary = fallback
            self.fallback = nil
            stateLock.unlock()
            return try body(fallback)
        }
    }

    private func performQuery(
        _ request: RazerReport, wait: TimeInterval, label: String, allowRemainingPacketsMismatch: Bool
    ) throws -> RazerReport {
        DiagnosticLog.shared.write(tag, "→ \(label): \(request)")
        var lastError: String?
        var rejected = 0
        var silent = 0
        for attempt in 1...5 {
            do {
                try withFallback { try $0.setFeature(request.bytes) }
            } catch let error as RazerError {
                if case .permissionDenied = error { throw error }
                lastError = error.localizedDescription
                DiagnosticLog.shared.write(tag, "  第 \(attempt) 次：\(lastError!)")
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            if wait > 0, interface.simulated == nil { Thread.sleep(forTimeInterval: wait) }
            let bytes: [UInt8]
            do {
                bytes = try withFallback { try $0.getFeature(length: RazerReport.length) }
            } catch let error as RazerError {
                lastError = error.localizedDescription
                DiagnosticLog.shared.write(tag, "  第 \(attempt) 次：\(lastError!)")
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            guard bytes.count == RazerReport.length, let response = try? RazerReport(bytes: bytes),
                  request.matches(response: response, allowRemainingPacketsMismatch: allowRemainingPacketsMismatch)
            else {
                lastError = "设备返回了错误、乱序或校验失败的报告；请关闭其他雷蛇控制软件后重试"
                DiagnosticLog.shared.write(tag, "  第 \(attempt) 次：响应校验失败 \(bytes.prefix(12).hexString)")
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            switch response.status {
            case 0x02:
                DiagnosticLog.shared.write(tag, "← 成功 args=\(response.rawArguments.prefix(12).hexString)")
                return response
            case 0x01:
                // OpenRazer treats BUSY as an accepted command.
                DiagnosticLog.shared.write(tag, "← 已接受（busy）")
                return response
            case 0x05:
                DiagnosticLog.shared.write(tag, "← 设备不支持此命令 (0x05)")
                throw RazerError.notSupported("设备不支持此命令 (0x05)")
            case 0x03:
                rejected += 1
                lastError = "设备拒绝了请求 (0x03)"
            case 0x04:
                silent += 1
                lastError = "设备没有回答此命令 (0x04)"
            default:
                lastError = String(format: "设备响应状态 0x%02X", response.status)
            }
            DiagnosticLog.shared.write(tag, "  第 \(attempt) 次：\(lastError!)")
            Thread.sleep(forTimeInterval: 0.01)
        }
        if rejected == 5 { throw RazerError.rejected(lastError ?? "") }
        // A dead endpoint fails every command; one silent command means the firmware lacks it.
        if silent == 5 { throw RazerError.timeout(lastError ?? "") }
        throw RazerError.transport(lastError ?? "特性报告查询失败")
    }
}

/// Dedicated run loop thread for HID input report callbacks.
final class HIDRunLoopThread: Thread, @unchecked Sendable {
    static let shared: HIDRunLoopThread = {
        let thread = HIDRunLoopThread()
        thread.name = "OpenSynapseMac.HIDInput"
        thread.start()
        thread.ready.wait()
        return thread
    }()

    private let ready = DispatchSemaphore(value: 0)
    private(set) var runLoop: CFRunLoop!

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A repeating timer keeps the run loop alive with no other sources attached.
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 3600, 3600, 0, 0) { _ in }
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
        ready.signal()
        CFRunLoopRun()
    }
}

/// Output/input report channel for the Kraken (37-byte) and BlackShark (64-byte) families.
public final class ReportChannel: @unchecked Sendable {
    public let interface: HIDInterface
    public let tag: String
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var opened = false
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var received: [[UInt8]] = []
    private let signal = DispatchSemaphore(value: 0)

    public init(interface: HIDInterface, tag: String) {
        self.interface = interface
        self.tag = tag
        queue = DispatchQueue(label: "OpenSynapseMac.channel.\(interface.registryId)")
    }

    deinit {
        if opened, let device = interface.device {
            IOHIDDeviceUnscheduleFromRunLoop(device, HIDRunLoopThread.shared.runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputBuffer?.deallocate()
    }

    private func ensureOpen() throws {
        guard !opened, interface.simulated == nil else { return }
        guard let device = interface.device else { throw RazerError.transport("没有 HID 设备句柄") }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw result == kIOReturnNotPermitted
                ? RazerError.permissionDenied("打开 HID 接口需要“输入监控”权限")
                : RazerError.transport("无法打开 HID 接口：\(describe(result))")
        }
        let size = max(interface.maxInputReportSize, 64)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        inputBuffer = buffer
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, _, _, reportId, report, length in
            guard let context else { return }
            let channel = Unmanaged<ReportChannel>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            // macOS includes the report ID in numbered reports; make sure it is there.
            if bytes.first != UInt8(truncatingIfNeeded: reportId), reportId != 0 {
                bytes.insert(UInt8(truncatingIfNeeded: reportId), at: 0)
            }
            channel.lock.lock()
            channel.received.append(bytes)
            if channel.received.count > 64 { channel.received.removeFirst() }
            channel.lock.unlock()
            channel.signal.signal()
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, HIDRunLoopThread.shared.runLoop, CFRunLoopMode.defaultMode.rawValue)
        opened = true
    }

    private func writeOutput(_ bytes: [UInt8]) throws {
        if let simulated = interface.simulated {
            if let reply = simulated.handleOutput(bytes) {
                lock.lock()
                received.append(reply)
                lock.unlock()
                signal.signal()
            }
            return
        }
        try ensureOpen()
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(interface.device!, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            throw RazerError.transport("输出报告失败：\(describe(result))")
        }
    }

    /// Numbered feature report I/O (HID LampArray). `bytes[0]` is the report ID.
    public func setFeature(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    DiagnosticLog.shared.write(self.tag, "→ 特性报告 \(bytes.prefix(16).hexString)")
                    if let simulated = self.interface.simulated {
                        simulated.handleFeature(bytes)
                        return continuation.resume()
                    }
                    try self.ensureOpen()
                    let result = bytes.withUnsafeBufferPointer {
                        IOHIDDeviceSetReport(self.interface.device!, kIOHIDReportTypeFeature, CFIndex(bytes[0]), $0.baseAddress!, $0.count)
                    }
                    guard result == kIOReturnSuccess else {
                        throw RazerError.transport("特性报告写入失败：\(describe(result))")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func getFeature(reportId: UInt8, length: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if let simulated = self.interface.simulated {
                        return continuation.resume(returning: simulated.featureReport(reportId))
                    }
                    try self.ensureOpen()
                    var buffer = [UInt8](repeating: 0, count: length)
                    buffer[0] = reportId
                    var size = CFIndex(length)
                    let result = buffer.withUnsafeMutableBufferPointer {
                        IOHIDDeviceGetReport(self.interface.device!, kIOHIDReportTypeFeature, CFIndex(reportId), $0.baseAddress!, &size)
                    }
                    guard result == kIOReturnSuccess else {
                        throw RazerError.transport("特性报告读取失败：\(describe(result))")
                    }
                    let bytes = Array(buffer.prefix(Int(size)))
                    DiagnosticLog.shared.write(self.tag, "← 特性报告 \(bytes.prefix(24).hexString)")
                    continuation.resume(returning: bytes)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func send(_ reports: [[UInt8]], delay: (([UInt8]) -> TimeInterval)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    for report in reports {
                        DiagnosticLog.shared.write(self.tag, "→ 输出报告 \(report.prefix(16).hexString)")
                        try self.writeOutput(report)
                        if let wait = delay?(report), wait > 0 { Thread.sleep(forTimeInterval: wait) }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Writes one output report and waits for the first input report that `match` accepts.
    public func exchange(_ report: [UInt8], timeout: TimeInterval, match: @escaping @Sendable ([UInt8]) -> Bool) async throws -> [UInt8]? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.ensureOpen()
                    self.lock.lock()
                    self.received.removeAll()
                    self.lock.unlock()
                    while self.signal.wait(timeout: .now()) == .success {}
                    DiagnosticLog.shared.write(self.tag, "→ 输出报告 \(report.prefix(16).hexString)")
                    try self.writeOutput(report)
                    let deadline = Date().addingTimeInterval(timeout)
                    while Date() < deadline {
                        if self.signal.wait(timeout: .now() + deadline.timeIntervalSinceNow) == .timedOut { break }
                        self.lock.lock()
                        let reports = self.received
                        self.received.removeAll()
                        self.lock.unlock()
                        if let hit = reports.first(where: match) {
                            DiagnosticLog.shared.write(self.tag, "← 输入报告 \(hit.prefix(20).hexString)")
                            continuation.resume(returning: hit)
                            return
                        }
                    }
                    DiagnosticLog.shared.write(self.tag, "← 超时未收到匹配的输入报告")
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
