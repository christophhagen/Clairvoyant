import Foundation

/**
 A remote metric is a single piece of state that is provided by an application running on a different server.

 Observing a remote metric merely states an intent to accept updates from another instance.
 The remote instance is responsible for pushing updates to the local observer.
 */
public final class RemoteMetric<T>: AnyMetric<T> where T: MetricValue {

    override var isRemote: Bool {
        true
    }

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil) {
        super.init(id: id, observer: .standard, name: name, description: description)
    }
}
