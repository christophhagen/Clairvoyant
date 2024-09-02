import Foundation

public protocol MetricBase {

    associatedtype Value: MetricValue

    associatedtype Storage

    /// The info of the metric
    var info: MetricInfo { get }

    init(storage: Storage, info: MetricInfo)
}

extension MetricBase {

    /// The additional details of the metric
    public var details: MetricDetails {
        info.details
    }

    /// The  name of the metric
    public var name: String? {
        info.details.name
    }

    /// A description of the metric content
    public var description: String? {
        info.description
    }

    /**
     Create a new metric.

     This constructor should be called by metric storage interfaces,
     which can ensure correct registration of metrics.
     Creating a metric manually may result in subsequent operations to fail, if the metric is not known to the metric storage.
     - Note: Metrics keep an `unowned` reference to the storage interface, so the storage object lifetime must exceed the lifetime of the metrics.
     */
    public init(storage: Storage, id: String, group: String, name: String? = nil, description: String? = nil) {
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
    public init(storage: Storage, id: MetricId, name: String? = nil, description: String? = nil) {
        let info = MetricInfo(id: id, valueType: Value.valueType, name: name, description: description)
        self.init(storage: storage, info: info)
    }

}
