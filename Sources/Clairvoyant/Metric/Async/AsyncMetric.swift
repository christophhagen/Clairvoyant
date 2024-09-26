import Foundation

/**
 A metric is a single piece of state that is provided by an application.
 Changes to the state can be used to update the metric,
 which will propagate the information to the collector for logging and further processing.

 The generic type can be any type that conforms to `MetricValue`,
 meaning it can be encoded/decoded and provides a description of its type.
 */
public struct AsyncMetric<Value>: MetricProtocol where Value: MetricValue {
    
    /// The info of the metric
    public let info: MetricInfo
    
    private unowned let storage: AsyncMetricStorage
    
    /**
     Create a new metric.
     
     This constructor should be called by metric storage interfaces,
     which can ensure correct registration of metrics.
     Creating a metric manually may result in subsequent operations to fail, if the metric is not known to the metric storage.
     - Note: Metrics keep an `unowned` reference to the storage interface, so the storage object lifetime must exceed the lifetime of the metrics.
     */
    public init(storage: any AsyncMetricStorage, info: MetricInfo) {
        self.storage = storage
        self.info = info
    }
    
    /**
     Set the metric to a new value with the current time
     */
    @discardableResult
    public func update(_ value: Value) async throws -> Bool {
        try await update(value.timestamped())
    }
    
    /**
     Set the metric to a new value and a timestamp
     */
    @discardableResult
    public func update(_ value: Value, timestamp: Date) async throws -> Bool {
        try await update(Timestamped(value: value, timestamp: timestamp))
    }
    
    /**
     Set the metric to a new value.
     */
    @discardableResult
    public func update(_ value: Timestamped<Value>) async throws -> Bool {
        guard value.shouldUpdate(currentValue: try await currentValue()) else {
            return false
        }
        try await storage.store(value, for: id)
        return true
    }
    
    /**
     Update the metric with a sequence of values.
     
     The given sequence is sorted and added to the log. Elements older than the last value are skipped.
     */
    public func update<S>(_ values: S) async throws where S: Sequence, S.Element == Timestamped<Value> {
        let valuesToAdd = values.valuesToUpdate(currentValue: try await currentValue())
        try await storage.store(valuesToAdd, for: id)
    }
    
    /**
     Get the current value of the metric.
     */
    public func currentValue() async throws -> Timestamped<Value>? {
        try await storage.lastValue(for: id)
    }
    
    /**
     Get the history of the metric values in the given interval, up to an optional limit of values.
     */
    public func history(from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) async throws -> [Timestamped<Value>] {
        try await storage.history(for: id, from: start, to: end, limit: limit)
    }
    
    /**
     Get the history of the metric values in the given interval, up to an optional limit of values.
     */
    public func history(in range: ClosedRange<Date>, order: MetricHistoryDirection = .olderToNewer, limit: Int? = nil) async throws -> [Timestamped<Value>] {
        switch order {
        case .newerToOlder:
            return try await storage.history(for: id, from: range.upperBound, to: range.lowerBound, limit: limit)
        case .olderToNewer:
            return try await storage.history(for: id, from: range.lowerBound, to: range.upperBound, limit: limit)
        }
    }
    
    /**
     Delete the historic values before a given date.
     - Parameter date: The point in time before which all values will be deleted.
     */
    public func deleteHistory(before date: Date = .distantFuture) async throws {
        try await storage.deleteHistory(for: id, before: date)
    }
    
    /**
     Add a callback to get notified about changes to the value of the metric.
     - Parameter changeCallback: The closure to call with the updated value
     - Parameter value: The updated timestamped value
     - Throws: An error by the storage interface if the callback could not be registered
     */
    public func onChange(_ changeCallback: @escaping (_ value: Timestamped<Value>) -> Void) async throws {
        try await storage.add(changeListener: changeCallback, for: id)
    }

    /**
     Add a callback to get notified about history deletions of the metric.
     - Parameter deleteCallback: The closure to call with the cutoff date
     - Parameter date: The date up to which the historic values have been deleted
     - Throws: An error by the storage interface if the callback could not be registered
     */
    public func onDelete(_ deleteCallback: @escaping (_ date: Date) -> Void) async throws {
        try await storage.add(deletionListener: deleteCallback, for: id)
    }
}

extension AsyncMetric: MetricBase {

}
