import Foundation

/**
 A protocol defining the minimum feature set of a storage interface for metrics.
 
 A metric has no internal storage, and delegates all operations to the storage interface.
 
 */
public protocol MetricStorage: AnyObject {
    
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
}
