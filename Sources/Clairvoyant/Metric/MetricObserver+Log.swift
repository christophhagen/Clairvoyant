#if canImport(Logging)
import Foundation
import Logging

extension MetricObserver {

    public func loggingBackend(label: String) -> LogHandler {
        let metric: Metric<String> = addMetric(id: label)
        return MetricLogHandler(label: label, metric: metric, format: loggingFormat)
    }
}

/**
 The format to apply when converting log messages to strings.
 */
public enum LogOutputFormat: String {

    /**
     Adds the level, source, file info, and message.

     The format has the form `[LEVEL][SOURCE:FILE:FUNCTION:LINE] MESSAGE`
     */
    case full = "full"

    /**
     Add most data, except the source is omitted, and only the last path component of the file

     The format has the form `[LEVEL][FILE_NAME:FUNCTION:LINE] MESSAGE`
     */
    case medium = "origin"

    /**
     Only the log level and message are saved.

     The format has the form `[LEVEL] MESSAGE`
     */
    case basic = "level"

    /**
     Only the message is saved.
     */
    case message = "message"
}

struct MetricLogHandler: LogHandler {


    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set(newValue) {
            metadata[metadataKey] = newValue
        }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt) {
            let text: String
            switch format {
            case .full:
                text = "[\(level)][\(source):\(file):\(function):\(line)] \(message)"
            case .medium:
                let f = file.components(separatedBy: "/").last!
                text = "[\(level)][\(f):\(function):\(line)] \(message)"
            case .basic:
                text = "[\(level)] \(message)"
            case .message:
                text = message.description
            }
            Task {
                try? await metric.update(text)
            }
    }

    var metadata: Logger.Metadata = [:]

    var logLevel: Logger.Level = .info

    private let label: String

    private let metric: Metric<String>

    private let format: LogOutputFormat

    init(label: String, metric: Metric<String>, format: LogOutputFormat) {
        self.label = label
        self.metric = metric
        self.format = format
    }
}

extension Logger.Level: CustomStringConvertible {

    public var description: String {
        switch self {
        case .trace:
            return "TRACE"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .critical:
            return "CRITICAL"
        }
    }
}

#endif
