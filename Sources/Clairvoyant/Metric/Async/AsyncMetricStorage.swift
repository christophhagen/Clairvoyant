import Foundation

public protocol AsyncMetricStorage: AnyObject {
    
    func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) async throws -> AsyncMetric<T>
    
    func delete(metric id: MetricId) async throws
    
    func store<T>(_ value: Timestamped<T>, for metric: AsyncMetric<T>) async throws
    
    func store<S, T>(_ values: S, for metric: AsyncMetric<T>) async throws where S: Sequence, S.Element == Timestamped<T>
    
    func lastValue<T>(for metric: AsyncMetric<T>) async throws -> Timestamped<T>?
    
    func history<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date, limit: Int?) async throws -> [Timestamped<T>]
    
    func deleteHistory<T>(for metric: AsyncMetric<T>, from start: Date, to end: Date) async throws
    
    func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: AsyncMetric<T>) async throws
}

extension AsyncMetricStorage {
    
    public func delete<T>(_ metric: Metric<T>) async throws {
        try await delete(metric: metric.id)
    }
    
    public func delete(metric id: String, group: String) async throws {
        try await delete(metric: .init(id: id, group: group))
    }
    
    public func metric<T>(id: MetricId, name: String? = nil, description: String? = nil, type: T.Type = T.self) async throws -> AsyncMetric<T> {
        try await metric(id, name: name, description: description, type: type)
    }
    
    public func metric<T>(id: String, group: String, name: String? = nil, description: String? = nil, type: T.Type = T.self) async throws -> AsyncMetric<T> {
        try await metric(.init(id: id, group: group), name: name, description: description, type: type)
    }
}
