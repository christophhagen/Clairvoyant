import Foundation
import Logging
import Clairvoyant

/**
 A wrapper around a `MetricObserver` to use as a logging backend.
 */
public struct MetricLogging {

    /**
     The wrapped observer handling the metrics created for each logger.
     */
    public let observer: MetricObserver

    /**
     The logging format to use when using the observer as a logging backend.

     The format determines the detail with which log messages are converted to text when being stored in a metric.
     The logging format is applied to any new `Logger` created with the backend.
     The format can be changed without affecting previously created `Logger`s.

     Default: `.basic`
     */
    public var loggingFormat: LogOutputFormat

    /**
     Wrap an observer for use as a logging backend.
     - Parameter observer: The observer to make metrics for each logger.
     - Parameter loggingFormat: The format to use for each log entry.
     */
    public init(observer: MetricObserver, loggingFormat: LogOutputFormat = .basic) {
        self.observer = observer
        self.loggingFormat = loggingFormat
    }

    /**
     The function to set as the backend.

     Set the function as the backend:
     ```
     let logging = MetricsLogging(observer: observer)
     LoggingSystem.bootstrap(logging.backend)
     ```
     - Parameter label: The label of the logger.
     */
    public func backend(label: String) -> LogHandler {
        let metric: Metric<String> = observer.addMetric(id: label)
        return MetricLogHandler(label: label, metric: metric, format: loggingFormat)
    }
}
