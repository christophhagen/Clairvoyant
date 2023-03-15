import Foundation
import Metrics
import Clairvoyant

final class RecorderMetric: RecorderHandler {

    let metric: Metric<Double>

    init(_ metric: Metric<Double>) {
        self.metric = metric
    }

    func record(_ value: Int64) {
        record(Double(value))
    }

    func record(_ value: Double) {
        Task {
            try await metric.update(value)
        }
    }
}

extension RecorderMetric: TimerHandler {

    func recordNanoseconds(_ duration: Int64) {
        record(duration)
    }
}
