import Foundation

public struct PropertyDescription: Codable {

    public let uniqueId: UInt32

    public let name: String

    public let type: PropertyType

    public let options: PropertyOptions

    public let updates: Update

    public let isLogged: Bool
}

extension PropertyDescription {

    public enum Update: Codable {

        case none

        /// The property is continuously available or computed when the property is read
        case continuous

        /// The property is updated in the specified interval
        case interval(TimeInterval)

        /// The property is only updated when an update is explicitly requested
        case manual
    }
}

extension PropertyDescription: Equatable {

    public static func ==(_ lhs: PropertyDescription, _ rhs: PropertyDescription) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }
}

extension PropertyDescription: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueId)
    }
}
