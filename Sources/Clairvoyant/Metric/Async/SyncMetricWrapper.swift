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

    public func metrics() throws -> [MetricInfo] {
        try storage.metrics()
    }

    public func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) throws -> AsyncMetric<T> where T : MetricValue {
        let syncMetric = try storage.metric(id, name: name, description: description, type: type)
        return .init(storage: self, info: syncMetric.info)
    }

    public func delete(metric id: MetricId) throws {
        try storage.delete(metric: id)
    }
    
    public func store<T>(_ value: Timestamped<T>, for metric: MetricId) throws where T: MetricValue {
        try storage.store(value, for: metric)
    }
    
    public func store<S, T>(_ values: S, for metric: MetricId) throws where S : Sequence, S.Element == Timestamped<T>, T: MetricValue {
        try storage.store(values, for: metric)
    }
    
    public func lastValue<T>(for metric: MetricId) throws -> Timestamped<T>? where T: MetricValue {
        try storage.lastValue(for: metric)
    }
    
    public func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int?) throws -> [Timestamped<T>] where T: MetricValue {
        try storage.history(for: metric, from: start, to: end, limit: limit)
    }
    
    public func deleteHistory(for metric: MetricId, from start: Date, to end: Date) throws {
        try storage.deleteHistory(for: metric, from: start, to: end)
    }
    
    public func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) throws where T: MetricValue {
        try storage.add(changeListener: changeListener, for:  metric)
    }
}
