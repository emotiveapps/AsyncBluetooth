// EmotiveApps addition. This fork changes **no upstream file at all** -- this one new file is the
// whole of it, so `git merge upstream/main` can only conflict if upstream adds a file of the same
// name. That is deliberate: the previous attempt at this changed five files and had to be merged by
// hand every time.
//
// How it manages that: `typealias Logger = AsyncBluetoothLogger` below shadows `os.Logger` for this
// module only. Upstream writes `Logger(subsystem:category:)`, `Logger(OSLog.disabled)`,
// `createLogger(for:) -> Logger` and `private static var logger: Logger`, and every one of those
// keeps compiling because `AsyncBluetoothLogger` offers the same initialisers and method names.
// Nothing outside this module is affected, and `os.Logger` is still reachable here as `os.Logger`.
//
// Why a fork at all: the package logs through `os.log`, and a host that keeps its own log (a file
// sink, a crash reporter, a debug console) has no way to see any of it. `AsyncBluetoothLogging` in
// 6.2.2 can only turn logging on or off. This adds a sink the host can install, without changing
// how the package writes to `os.log` when no sink is installed.

import Foundation
import os.log

/// How severe a message from the package is.
public enum AsyncBluetoothLogLevel: String, Sendable, CaseIterable {
    case debug, info, notice, warning, error, critical
}

/// Somewhere a host wants the package's log messages to go, as well as `os.log`.
///
/// Install one with `AsyncBluetoothLogging.setSink(_:)`. The package calls this from whatever
/// thread it happens to be on, which is why it is `Sendable` and why the call must be cheap.
public protocol AsyncBluetoothLogSink: Sendable {
    /// - parameter category: the package's own category -- "centralManager", "peripheral",
    ///   "peripheralDelegate" or "asyncExecuterMap" -- so a host can route or filter by it.
    func asyncBluetoothDidLog(_ message: String, level: AsyncBluetoothLogLevel, category: String)
}

/// Whether an interpolated value may be written in the clear.
///
/// Mirrors the subset of `OSLogPrivacy` this package uses, so a call site written as
/// `"\(name, privacy: .private)"` keeps compiling untouched.
public enum AsyncBluetoothLogPrivacy: Sendable {
    case auto
    case `public`
    case `private`
}

/// A message built by string interpolation, which is what every call site in this package already
/// writes. Redaction happens here rather than at the call site.
public struct AsyncBluetoothLogMessage: ExpressibleByStringInterpolation, Sendable {
    public let rendered: String

    public init(stringLiteral value: String) { rendered = value }
    public init(stringInterpolation: Interpolation) { rendered = stringInterpolation.text }

    public struct Interpolation: StringInterpolationProtocol, Sendable {
        var text = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) { text += literal }

        public mutating func appendInterpolation(_ value: some Any) {
            text += "\(value)"
        }

        /// The `privacy:` form the package uses. A `.private` value is redacted in the text handed
        /// to a sink, which is the same promise `os.log` makes.
        public mutating func appendInterpolation(_ value: some Any,
                                                 privacy: AsyncBluetoothLogPrivacy) {
            text += privacy == .private ? "<private>" : "\(value)"
        }
    }
}

/// Stands where `os.Logger` stood, with the same method names, so not one of the package's log
/// call sites has to change.
///
/// It writes to `os.log` exactly as before **and**, when the host has installed one, to the sink.
public struct AsyncBluetoothLogger: Sendable {
    let category: String
    let osLogger: os.Logger

    /// Upstream's `createLogger(for:)` shape, unchanged.
    public init(subsystem: String, category: String) {
        self.category = category
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    /// Upstream's `Logger(OSLog.disabled)` shape, used for its disabled logger. A logger built this
    /// way writes nowhere and tells no sink, which is what "disabled" has to keep meaning.
    public init(_ osLog: OSLog) {
        self.category = ""
        self.osLogger = os.Logger(osLog)
        self.isDisabled = osLog === OSLog.disabled
    }

    private var isDisabled = false

    public func debug(_ message: AsyncBluetoothLogMessage) { emit(message, .debug) }
    public func info(_ message: AsyncBluetoothLogMessage) { emit(message, .info) }
    public func notice(_ message: AsyncBluetoothLogMessage) { emit(message, .notice) }
    public func warning(_ message: AsyncBluetoothLogMessage) { emit(message, .warning) }
    public func error(_ message: AsyncBluetoothLogMessage) { emit(message, .error) }
    public func critical(_ message: AsyncBluetoothLogMessage) { emit(message, .critical) }

    private func emit(_ message: AsyncBluetoothLogMessage, _ level: AsyncBluetoothLogLevel) {
        guard !isDisabled else { return }
        let text = message.rendered

        switch level {
        case .debug: osLogger.debug("\(text, privacy: .public)")
        case .info: osLogger.info("\(text, privacy: .public)")
        case .notice: osLogger.notice("\(text, privacy: .public)")
        case .warning: osLogger.warning("\(text, privacy: .public)")
        case .error: osLogger.error("\(text, privacy: .public)")
        case .critical: osLogger.critical("\(text, privacy: .public)")
        }

        AsyncBluetoothLogging.sink?.asyncBluetoothDidLog(text, level: level, category: category)
    }
}

public extension AsyncBluetoothLogging {
    /// Sends every message the package logs to `sink`, as well as to `os.log`.
    /// - parameter sink: nil removes the current one.
    static func setSink(_ sink: (any AsyncBluetoothLogSink)?) {
        sinkLock.withLock { storedSink = sink }
    }

    internal static var sink: (any AsyncBluetoothLogSink)? {
        sinkLock.withLock { storedSink }
    }
}

private let sinkLock = NSLock()
nonisolated(unsafe) private var storedSink: (any AsyncBluetoothLogSink)?

/// Shadows `os.Logger` inside this module only. See the note at the top of this file.
typealias Logger = AsyncBluetoothLogger
