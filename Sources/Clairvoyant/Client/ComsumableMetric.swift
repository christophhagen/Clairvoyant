import Foundation

/**
 An object to access a specific metric from a server
 */
public actor ConsumableMetric<T> where T: MetricValue {

    /// The main consumer of the server
    public let consumer: MetricConsumer

    /// The description of the metric
    public let description: MetricDescription

    /// The unique if of the metric
    public nonisolated var id: MetricId {
        description.id
    }

    /**
     Create a handle for a metric.
     - Parameter consumer: The consumer of the server
     - Parameter id: The id of the metric
     - Parameter name: The optional name of the metric
     - Parameter description: A textual description of the metric
     */
    public init(consumer: MetricConsumer, id: MetricId, name: String? = nil, description: String? = nil) {
        self.consumer = consumer
        self.description = .init(id: id, dataType: T.valueType, name: name, description: description)
    }

    /**
     Create a handle for a metric.
     - Parameter consumer: The consumer of the server
     - Parameter description: The info of the metric
     */
    public init(consumer: MetricConsumer, description: MetricDescription) {
        self.consumer = consumer
        self.description = description
    }

    /**
     Get the last value of the metric from the server.
     - Returns: The timestamped last value of the metric, if one exists
     - Throws: `MetricError`
     */
    public func lastValue() async throws -> Timestamped<T>? {
        try await consumer.lastValue(for: id)
    }

    /**
     Get the history of the metric value in a specified range
     - Returns: The timestamped values within the range.
     - Throws: `MetricError`
     */
    public func history(in range: ClosedRange<Date>) async throws -> [Timestamped<T>] {
        try await consumer.history(for: id, in: range)
    }
}

extension ConsumableMetric: GenericConsumableMetric {

    public func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R : MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        guard let value = try await self.lastValue() else {
            return nil
        }
        guard let converted = value as? Timestamped<R>? else {
            throw MetricError.typeMismatch
        }
        return converted
    }

    public func history<R>(in range: ClosedRange<Date>, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        let values = try await self.history(in: range)
        return try values.map {
            guard let result = $0 as? Timestamped<R> else {
                throw MetricError.typeMismatch
            }
            return result
        }
    }

    public func lastValueData() async throws -> Data? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        return data
    }

    public func lastValueDescription() async throws -> Timestamped<String>? {
        guard let value = try await lastValue() else {
            return nil
        }
        return value.mapValue { "\($0)" }
    }

    public func historyDescription(in range: ClosedRange<Date>) async throws -> [Timestamped<String>] {
        try await history(in: range).map { $0.mapValue(String.init(describing:)) }
    }
}
