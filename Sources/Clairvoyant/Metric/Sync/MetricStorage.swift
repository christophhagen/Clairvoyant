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
    
    func store<T>(_ value: Timestamped<T>, for metric: Metric<T>) throws
    
    func store<S, T>(_ values: S, for metric: Metric<T>) throws where S: Sequence, S.Element == Timestamped<T>
    
    func lastValue<T>(for metric: Metric<T>) throws -> Timestamped<T>?
    
    func history<T>(for metric: Metric<T>, from start: Date, to end: Date, limit: Int?) throws -> [Timestamped<T>]
    
    func deleteHistory<T>(for metric: Metric<T>, from start: Date, to end: Date) throws
    
    func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: Metric<T>) throws
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
