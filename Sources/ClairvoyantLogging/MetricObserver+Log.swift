import Foundation
import Logging
import Clairvoyant

public struct MetricLogging {

    public let observer: MetricObserver

    /**
     The logging format to use when using the observer as a logging backend.

     The format determines the detail with which log messages are converted to text when being stored in a metric.
     The logging format is applied to any new `Logger` created with the backend.
     The format can be changed without affecting previously created `Logger`s.

     Default: `.basic`
     */
    public var loggingFormat: LogOutputFormat

    public init(observer: MetricObserver, loggingFormat: LogOutputFormat = .basic) {
        self.observer = observer
        self.loggingFormat = loggingFormat
    }

    public func backend(label: String) -> LogHandler {
        let metric: Metric<String> = observer.addMetric(id: label)
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
                text = "[\(level.text)][\(source):\(file):\(function):\(line)] \(message)"
            case .medium:
                let f = file.components(separatedBy: "/").last!
                text = "[\(level.text)][\(f):\(function):\(line)] \(message)"
            case .basic:
                text = "[\(level.text)] \(message)"
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

private extension Logger.Level {

    var text: String {
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
