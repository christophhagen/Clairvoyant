import Foundation

public final class ConsumableMetric<T> where T: MetricValue {

    let consumer: MetricConsumer

    public let description: MetricDescription

    public var id: MetricId {
        description.id
    }

    init(consumer: MetricConsumer, id: MetricId, name: String? = nil, description: String? = nil) {
        self.consumer = consumer
        self.description = .init(id: id, dataType: T.valueType, name: name, description: description)
    }

    public func lastValue() async throws -> Timestamped<T>? {
        try await consumer.lastValue(for: id)
    }

    public func history(in range: ClosedRange<Date>) async throws -> [Timestamped<T>] {
        try await consumer.history(for: id, in: range)
    }
}
