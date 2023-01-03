import Foundation

public enum PropertyUpdate<T> where T: PropertyValueType {

    /// The property is continuously available or computed when the property is read
    case continuous

    /// The property is updated in the specified interval
    case interval(TimeInterval, PropertyUpdateCallback<T>)

    /// The property is only updated when an update is explicitly requested
    case manual(PropertyUpdateCallback<T>)

    var description: PropertyDescription.Update {
        switch self {
        case .continuous: return .continuous
        case .interval(let interval, _): return .interval(interval)
        case .manual: return .manual
        }
    }

    var updateCallback: PropertyUpdateCallback<T>? {
        switch self {
        case .continuous:
            return nil
        case .interval(_, let propertyUpdateCallback):
            return propertyUpdateCallback
        case .manual(let propertyUpdateCallback):
            return propertyUpdateCallback
        }
    }
}
