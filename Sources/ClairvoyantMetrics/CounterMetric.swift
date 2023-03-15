import Foundation
import Metrics
import Clairvoyant

final class CounterMetric: CounterHandler {

    let metric: Metric<Int>

    init(_ metric: Metric<Int>) {
        self.metric = metric
    }

    func increment(by amount: Int64) {
        Task {
            let oldValue = await metric.lastValue()?.value ?? 0
            let result = oldValue.addingReportingOverflow(Int(amount))
            let newValue = result.overflow ? Int.max : result.partialValue
            try await metric.update(newValue)
        }
    }

    func reset() {
        Task {
            try await metric.update(0)
        }
    }
}
