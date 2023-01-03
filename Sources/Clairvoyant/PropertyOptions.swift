import Foundation

/**
 Options for properties
 */
public struct PropertyOptions: OptionSet, Codable, Equatable, Hashable {

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /** The property can be read */
    public static let isReadable = PropertyOptions(rawValue: 1 << 0)

    /** The property can be written to */
    public static let isWritable = PropertyOptions(rawValue: 1 << 1)

    /** The property provides a log of past values */
    public static let isLogged = PropertyOptions(rawValue: 1 << 2)

    /** The property can be manually forced to update */
    public static let allowsManualUpdate = PropertyOptions(rawValue: 1 << 3)
}
