import Foundation

/**
 A wrapper to use a synchronous `MetricStorage` as an `AsyncMetricStorage`.
 */
public class MetricStorageWrapper<Storage> where Storage: MetricStorage {

    let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
    }

    private func convert<T>(_ asyncMetric: AsyncMetric<T>) throws -> Metric<T> {
        try storage.metric(info: asyncMetric.info)
    }
}

extension MetricStorageWrapper: AsyncMetricStorage {

    public func metrics() async throws -> [MetricInfo] {
        try storage.metrics()
    }

    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) async throws -> AsyncMetric<T> where T : MetricValue {
        .init(storage: self, id: id, name: name, description: description)
    }

    public func delete(metric id: MetricId) async throws {
        try storage.delete(metric: id)
    }
    
    public func store<T>(_ value: Timestamped<T>, for metric: MetricId) async throws where T: MetricValue {
        try storage.store(value, for: metric)
    }
    
    public func store<S, T>(_ values: S, for metric: MetricId) async throws where S : Sequence, S.Element == Timestamped<T>, T: MetricValue {
        try storage.store(values, for: metric)
    }
    
    public func lastValue<T>(for metric: MetricId) async throws -> Timestamped<T>? where T: MetricValue {
        try storage.lastValue(for: metric)
    }
    
    public func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int?) async throws -> [Timestamped<T>] where T: MetricValue {
        try storage.history(for: metric, from: start, to: end, limit: limit)
    }
    
    public func deleteHistory<T>(for metric: MetricId, type: T.Type, from start: Date, to end: Date) async throws where T: MetricValue {
        try storage.deleteHistory(for: metric, type: type, from: start, to: end)
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) async throws where T: MetricValue {
        try storage.add(changeListener: changeListener, for:  metric)
    }
}
