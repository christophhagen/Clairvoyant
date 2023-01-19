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
     */
    public init(_ id: String) {
        super.init(id: id, observer: .standard)
    }
}
