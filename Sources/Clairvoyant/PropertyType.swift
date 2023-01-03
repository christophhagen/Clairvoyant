import Foundation

/**
 The data type of a property.
 */
public enum PropertyType: UInt8, Codable, Equatable, Hashable {

    /// The property consists of an integer
    case integer = 1

    /// The property consists of a double
    case double = 2

    /// The property consists of a boolean
    case bool = 3

    /// The property consists of a string
    case string = 4

    /// The property is an enumeration
    case enumeration = 5

    /// The property is a complex object
    case object = 6
}
