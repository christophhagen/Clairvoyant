import Foundation

public protocol GenericConsumableMetric {

    /// The consumer associated with the metric
    var consumer: MetricConsumer { get }

    /// The info of the metric
    var description: MetricDescription { get }

    /**
     Get the encoded data of the last value.
     - Returns: The encoded data of the timestamped last value, or `nil`
     */
    func lastValueData() async throws -> Data?

    /**
     Get a textual description of the last value.
     - Returns: A description of the timestamped last value, or `nil`
     */
    func lastValueDescription() async throws -> Timestamped<String>?

    /**
     Get the timestamped last value as a specific type.
     - Parameter type: The type to decode the last value data
     - Note: If the type does not match the underlying data, then an error will be thrown
     */
    func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R: MetricValue

    func history<R>(in range: ClosedRange<Date>, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue

    func historyDescription(in range: ClosedRange<Date>) async throws -> [Timestamped<String>]
}

extension GenericConsumableMetric {

    /// The unique if of the metric
    public var id: MetricId {
        description.id
    }

    /// The data type of the values in the metric
    public var dataType: MetricType {
        description.dataType
    }

    /// A name to display for the metric
    public var name: String? {
        description.name
    }

    /**
     Describe the data of an encoded timestamped value.
     - Parameter data: The encoded data
     - Parameter type: The type of the encoded timestamped value
     - Returns: A timestamped textual description of the encoded value.
     */
    public func describe<T>(_ data: Data, as type: T.Type) -> Timestamped<String> where T: MetricValue {
        consumer.describe(data, as: type)
    }
}
