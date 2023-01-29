import Foundation

/**
 A metric is a single piece of state that is provided by an application.
 Changes to the state can be used to update the metric,
 which will propagate the information to the collector for logging and further processing.

 The generic type can be any type that conforms to `MetricValue`,
 meaning it can be encoded/decoded and provides a description of its type.
 */
public final class Metric<T>: AnyMetric<T> where T: MetricValue {

    /**
     Create a new metric.
     - Parameter id: The unique id of the metric.
     - Parameter dataType: The raw type of the values contained in the metric
     - Parameter name: A descriptive name of the metric
     - Parameter description: A textual description of the metric
     */
    public init(_ id: String, containing dataType: T.Type = T.self, name: String? = nil, description: String? = nil) {
        super.init(id: id, observer: .standard, name: name, description: description)
        _lastValue = observer?.getLastValue(for: self)
    }

    init(unobserved id: String, name: String?, description: String?) {
        super.init(id: id, observer: nil, name: name, description: description)
    }

    /// The last value of the metric
    private var _lastValue: Timestamped<T>? = nil

    public override func lastValue() -> Timestamped<T>? {
        _lastValue ?? observer?.getLastValue(for: self)
    }
    /**
     Update the value of the metric.

     This function will create a new timestamped value and forward it for logging to the observer.
     - Parameter value: The new value to set.
     - Parameter timestamp: The timestamp of the value (defaults to the current time)
     - Returns: `true` if the value was stored, `false` if either no observer is registered, or the observer failed to store the value.
     */
    @discardableResult
    public func update(_ value: T, timestamp: Date = Date()) -> Bool {
        guard let observer else {
            return false
        }
        if let lastValue = _lastValue?.value, lastValue == value {
            return true
        }
        let dataPoint = Timestamped(timestamp: timestamp, value: value)
        guard observer.update(dataPoint, for: self) else {
            return false
        }
        _lastValue = dataPoint
        return true
    }
}
