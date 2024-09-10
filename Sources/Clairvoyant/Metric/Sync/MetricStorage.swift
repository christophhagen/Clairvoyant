import Foundation

/**
 A protocol defining the minimum feature set of a storage interface for metrics.
 
 A metric has no internal storage, and delegates all operations to the storage interface.
 
 */
public protocol MetricStorage: AnyObject {
    
    /**
     List all metrics in the storage.
     */
    func metrics() throws -> [MetricInfo]
    
    /**
     Create a handle to a metric.
     
     If a metric doesn't exist, then it will be created.
     If a metric with the same `id` already exists, then the types must match.
     Changes for `name` and `description` will update the metric info, but will not be propagated to already existing handles.
     
     - Note: Metrics should be thread-safe, so that multiple metric handles can be used simultaneously to update the same metric.
     
     - Parameter id: The unique id of the metric
     - Parameter name: An optional descriptive name of the metric
     - Parameter description: An optional description of the metric content
     - Parameter type: The type of data stored in the metric
     */
    func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) throws -> Metric<T>
    
    func delete(metric id: MetricId) throws
    
    func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T: MetricValue

    func store<S, T>(_ values: S, for metric: MetricId) throws where S: Sequence, S.Element == Timestamped<T>, T: MetricValue

    /**
     Return the timestamp of the last value of a metric.
     */
    func timestampOfLastValue(for metric: MetricId) throws -> Date?

    func lastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T: MetricValue

    func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int?) throws -> [Timestamped<T>] where T: MetricValue

    func deleteHistory(for metric: MetricId, from start: Date, to end: Date) throws

    /**
     Add a listener to get notified about new values added to a metric.
     - Note: The listener is only called for the last value when inserting multiple values using ``store(_:for:)``
     */
    func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) throws where T: MetricValue

    /**
     Set the global listener for change actions.

     Only a single global listener must be stored.
     */
    func setGlobalChangeListener(_ listener: @escaping (_ id: MetricId, _ newValueDate: Date) -> Void) throws

    /**
     Add a listener to get notified about history deletion actions.
     - The callback is called for each invocation of ``deleteHistory(for:from:to:)`` if the metric matches
     */
    func add(deletionListener: @escaping (ClosedRange<Date>) -> Void, for metric: MetricId) throws

    /**
     Set the global listener for deletion actions.

     Only a single global listener must be stored.
     */
    func setGlobalDeletionListener(_ listener: @escaping (_ id: MetricId, _ range: ClosedRange<Date>) -> Void) throws
}

extension MetricStorage {
    
    public func delete<T>(_ metric: Metric<T>) throws {
        try delete(metric: metric.id)
    }
    
    public func delete(metric id: String, group: String) throws {
        try delete(metric: .init(id: id, group: group))
    }
    
    public func metric<T>(id: MetricId, name: String? = nil, description: String? = nil, type: T.Type = T.self) throws -> Metric<T> {
        try metric(id, name: name, description: description, type: type)
    }
    
    public func metric<T>(id: String, group: String, name: String? = nil, description: String? = nil, type: T.Type = T.self) throws -> Metric<T> {
        try metric(.init(id: id, group: group), name: name, description: description, type: type)
    }

    public func metric<T>(info: MetricInfo, type: T.Type = T.self) throws -> Metric<T> {
        try metric(info.id, name: info.name, description: info.description, type: T.self)
    }
}
