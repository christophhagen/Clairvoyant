import Foundation
import Clairvoyant
import Logging

/**
 A small wrapper to act as a logger while forwarding log messages to a metric.
 */
struct MetricLogHandler: LogHandler {

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
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
