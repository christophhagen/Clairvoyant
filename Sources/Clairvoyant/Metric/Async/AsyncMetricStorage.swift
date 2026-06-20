import Foundation

public protocol AsyncMetricStorage: AnyObject {
    
    /**
     List all metrics in the storage.
     */
    func metrics() async throws -> [MetricInfo]
    
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
    func metric<T>(_ id: MetricId, name: String?, description: String?, type: T.Type) async throws -> AsyncMetric<T>
    
    func delete(metric id: MetricId) async throws
    
    func store<T>(_ value: Timestamped<T>, for metric: MetricId) async throws where T: MetricValue

    func store<S, T>(_ values: S, for metric: MetricId) async throws where S: Sequence, S.Element == Timestamped<T>, T: MetricValue

    func timestampOfLastValue(for metric: MetricId) async throws -> Date?
    
    func lastValue<T>(for metric: MetricId) async throws -> Timestamped<T>? where T: MetricValue

    func history<T>(for metric: MetricId, from start: Date, to end: Date, limit: Int?) async throws -> [Timestamped<T>] where T: MetricValue

    /**
     Delete historic data before a given date
     - Parameter metric: The id of the metric for which to delete history data
     - Parameter date: The point in time up to which values should be deleted
     */
    func deleteHistory(for metric: MetricId, before date: Date) async throws

    /**
     Add a listener to get notified about new values added to a metric.
     - Note: The listener is only called for the last value when inserting multiple values using ``store(_:for:)``
     */
    func add<T>(changeListener: @escaping (Timestamped<T>) -> Void, for metric: MetricId) async throws where T: MetricValue

    /**
     Set the global listener for change actions.

     Only a single global listener must be stored.
     */
    func setGlobalChangeListener(_ listener: @escaping (_ id: MetricId, _ newValueDate: Date) -> Void) async throws

    /**
     Add a listener to get notified about history deletion actions.
     - The callback is called for each invocation of ``deleteHistory(for:before:)`` if the metric matches
     */
    func add(deletionListener: @escaping (Date) -> Void, for metric: MetricId) async throws

    /**
     Set the global listener for deletion actions.

     Only a single global listener must be stored.
     - The callback is called for each invocation of ``deleteHistory(for:before:)``
     */
    func setGlobalDeletionListener(_ listener: @escaping (_ id: MetricId, _ range: Date) -> Void) async throws

}

extension AsyncMetricStorage {
    
    public func delete<T>(_ metric: AsyncMetric<T>) async throws {
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
