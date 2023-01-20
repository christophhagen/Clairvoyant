import Foundation

public final class ConsumableMetric<T> where T: MetricValue {

    let consumer: MetricConsumer

    public let id: MetricId

    init(consumer: MetricConsumer, id: MetricId) {
        self.consumer = consumer
        self.id = id
    }

    public func lastValue() async throws -> Timestamped<T>? {
        try await consumer.lastValue(for: id)
    }

    public func history(in range: ClosedRange<Date>) async throws -> [Timestamped<T>] {
        try await consumer.history(for: id, in: range)
    }
}
