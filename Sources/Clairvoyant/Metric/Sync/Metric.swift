import Foundation

/**
 A metric is a single piece of state that is provided by an application.
 Changes to the state can be used to update the metric,
 which will propagate the information to the collector for logging and further processing.

 The generic type can be any type that conforms to `MetricValue`,
 meaning it can be encoded/decoded and provides a description of its type.
 */
public struct Metric<Value>: MetricProtocol where Value: MetricValue {
    
    /// The info of the metric
    public let info: MetricInfo
    
    /// A reference to the storage to delegate all operations
    private unowned let storage: MetricStorage
    
    /**
     Create a new metric.
     
     This constructor should be called by metric storage interfaces,
     which can ensure correct registration of metrics.
     Creating a metric manually may result in subsequent operations to fail, if the metric is not known to the metric storage.
     - Note: Metrics keep an `unowned` reference to the storage interface, so the storage object lifetime must exceed the lifetime of the metrics.
     */
    public init(storage: any MetricStorage, id: String, group: String, name: String? = nil, description: String? = nil) {
        let id = MetricId(id: id, group: group)
        self.init(storage: storage, id: id, name: name, description: description)
    }
    
    /**
     Create a new metric.
     
     This constructor should be called by metric storage interfaces,
     which can ensure correct registration of metrics.
     Creating a metric manually may result in subsequent operations to fail, if the metric is not known to the metric storage.
     - Note: Metrics keep an `unowned` reference to the storage interface, so the storage object lifetime must exceed the lifetime of the metrics.
     */
    public init(storage: any MetricStorage, id: MetricId, name: String? = nil, description: String? = nil) {
        let info = MetricInfo(id: id, valueType: Value.valueType, name: name, description: description)
        self.init(storage: storage, info: info)
    }
    
    /**
     Create a new metric.
     
     This constructor should be called by metric storage interfaces,
     which can ensure correct registration of metrics.
     Creating a metric manually may result in subsequent operations to fail, if the metric is not known to the metric storage.
     - Note: Metrics keep an `unowned` reference to the storage interface, so the storage object lifetime must exceed the lifetime of the metrics.
     */
    public init(storage: any MetricStorage, info: MetricInfo) {
        self.storage = storage
        self.info = info
    }
    
    /**
     Set the metric to a new value with the current time
     - Parameter value: The value to set
     */
    @discardableResult
    public func update(_ value: Value) throws -> Bool {
        try update(value.timestamped())
    }
    
    /**
     Set the metric to a new value and a timestamp
     */
    @discardableResult
    public func update(_ value: Value, timestamp: Date) throws -> Bool {
        try update(Timestamped(value: value, timestamp: timestamp))
    }
    
    /**
     Set the metric to a new value.
     - Parameter value: The timestamped value to set
     */
    @discardableResult
    public func update(_ value: Timestamped<Value>) throws -> Bool {
        if let lastValue = try currentValue() {
            guard value.isDifferentAndNewer(than: lastValue) else {
                return false
            }
        }
        try storage.store(value, for: self)
        return true
    }
    
    /**
     Update the metric with a sequence of values.
     
     The given sequence is sorted and added to the log.
     Elements older than the last value are skipped, as are values that are equal to the previous ones
     */
    public func update<S>(_ values: S) throws where S: Sequence, S.Element == Timestamped<Value> {
        var lastValue = try currentValue()
        var valuesToAdd: [Timestamped<Value>] = []
        for value in values.sorted(using: { $0.timestamp }) {
            guard let last = lastValue else {
                valuesToAdd.append(value)
                lastValue = value
                continue
            }
            guard value.isDifferentAndNewer(than: last) else {
                continue
            }
            valuesToAdd.append(value)
            lastValue = value
        }
        try storage.store(valuesToAdd, for: self)
    }
    
    /**
     Get the current value of the metric.
     - Returns: The current value of the metric (timestamped), if it exists
     */
    public func currentValue() throws -> Timestamped<Value>? {
        try storage.lastValue(for: self)
    }
    
    /**
     Get the history of the metric values in the given interval, up to an optional limit of values.
     */
    public func history(from start: Date = .distantPast, to end: Date = .distantFuture, limit: Int? = nil) throws -> [Timestamped<Value>] {
        try storage.history(for: self, from: start, to: end, limit: limit)
    }
    
    /**
     Get the history of the metric values in the given interval, up to an optional limit of values.
     */
    public func history(in range: ClosedRange<Date>, order: MetricHistoryDirection = .olderToNewer, limit: Int? = nil) throws -> [Timestamped<Value>] {
        switch order {
        case .newerToOlder:
            return try storage.history(for: self, from: range.upperBound, to: range.lowerBound, limit: limit)
        case .olderToNewer:
            return try storage.history(for: self, from: range.lowerBound, to: range.upperBound, limit: limit)
        }
    }
    
    /**
     Delete the history in the given interval (including start and end)
     */
    public func deleteHistory(from start: Date = .distantPast, to end: Date = .distantFuture) throws {
        try storage.deleteHistory(for: self, from: start, to: end)
    }
    
    /**
     Add a callback to get notified about changes to the value of the metric.
     - Parameter changeCallback: The closure to call with the updated value
     - Parameter value: The updated timestamped value
     - Throws: An error by the storage interface if the callback could not be registered
     */
    public func onChange(_ changeCallback: @escaping (_ value: Timestamped<Value>) -> Void) throws {
        try storage.add(changeListener: changeCallback, for: self)
    }
}
