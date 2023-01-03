import Foundation


typealias AbstractPropertyRead = () async throws -> Data
typealias AbstractPropertyWrite = (Data) async throws -> Void
typealias AbstractPropertyUpdate = () async throws -> Void

struct PropertyReference {

    let name: String

    var read: AbstractPropertyRead?

    var write: AbstractPropertyWrite?

    let type: PropertyType

    var update: Update

    let isLogged: Bool

    let allowsManualUpdate: Bool

    var nextUpdate: Date?

    /// The file used for logging
    var fileHandle: FileHandle?

    /// The last value of the property, to compare before logging
    var lastValue: Data?

    mutating func didUpdate() {
        guard case let .interval(delay, _) = update else {
            return
        }
        nextUpdate = (nextUpdate ?? Date()).advanced(by: delay)
    }

    func description(uniqueId: UInt32) -> PropertyDescription {
        var options = PropertyOptions()
        if read != nil { options.insert(.isReadable) }
        if write != nil { options.insert(.isWritable) }
        if allowsManualUpdate { options.insert(.allowsManualUpdate) }
        return .init(uniqueId: uniqueId, name: name, type: type, options: options, updates: update.description, isLogged: isLogged)
    }

    enum Update {
        /// The property is continuously available or computed when the property is read
        case continuous

        /// The property is updated in the specified interval
        case interval(TimeInterval, AbstractPropertyUpdate)

        /// The property is only updated when an update is explicitly requested
        case manual(AbstractPropertyUpdate)

        var description: PropertyDescription.Update {
            switch self {
            case .continuous: return .continuous
            case .interval(let interval, _): return .interval(interval)
            case .manual: return .manual
            }
        }

        var updateCallback: AbstractPropertyUpdate? {
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

}
