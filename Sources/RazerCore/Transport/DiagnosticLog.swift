import Foundation

public struct DiagnosticEntry: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let tag: String
    public let message: String
}

/// In-memory diagnostic ring buffer. Every request the app sends and every answer it gets is
/// recorded so a failing control can be told apart from one that never left the app.
public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog()
    public static let didChange = Notification.Name("OpenSynapseMac.DiagnosticLog.didChange")

    private let lock = NSLock()
    private var buffer: [DiagnosticEntry] = []
    private var nextId = 0
    private let capacity = 2000
    private var notifyScheduled = false

    public func write(_ tag: String, _ message: String) {
        lock.lock()
        buffer.append(DiagnosticEntry(id: nextId, date: Date(), tag: tag, message: message))
        nextId += 1
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let shouldNotify = !notifyScheduled
        notifyScheduled = true
        lock.unlock()
        if shouldNotify {
            // Coalesce bursts (a refresh sends dozens of requests) into one UI update.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.notifyScheduled = false
                self.lock.unlock()
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }

    public var entries: [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    public func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { "\(formatter.string(from: $0.date)) [\($0.tag)] \($0.message)" }.joined(separator: "\n")
    }
}
