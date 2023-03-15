import Foundation
import Metrics
import Clairvoyant

/**
 A wrapper for a `MetricsObserver` to use as a backend for `swift-metrics`.

 Set the provider as the backend:

 ```
 import Clairvoyant
 import ClairvoyantMetrics

 let observer = MetricObserver(...)
 let metrics = MetricsProvider(observer: observer)
 MetricsSystem.bootstrap(metrics)
 ```
 */
public final class MetricsProvider: MetricsFactory {

    private let observer: MetricObserver

    /**
     Create a metric provider with an observer.

     - Parameter observer: The observer to handle the metrics.
     */
    public init(observer: MetricObserver) {
        self.observer = observer
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        let metric: Metric<Int> = observer.addMetric(id: label)
        return CounterMetric(metric)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let metric: Metric<Double> = observer.addMetric(id: label)
        return RecorderMetric(metric)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        let metric: Metric<Double> = observer.addMetric(id: label)
        return RecorderMetric(metric)
    }

    public func destroyCounter(_ handler: CounterHandler) {
        guard let counter = handler as? CounterMetric else {
            return
        }
        Task {
            await counter.metric.removeFromObserver()
        }
    }

    public func destroyRecorder(_ handler: RecorderHandler) {
        guard let recorder = handler as? RecorderMetric else {
            return
        }
        Task {
            await recorder.metric.removeFromObserver()
        }
    }

    public func destroyTimer(_ handler: TimerHandler) {
        guard let recorder = handler as? RecorderMetric else {
            return
        }
        Task {
            await recorder.metric.removeFromObserver()
        }
    }
}
