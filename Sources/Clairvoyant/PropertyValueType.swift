import Foundation

public protocol PropertyValueType: Codable, Equatable, Timestampable {

    static var type: PropertyType { get }
}

extension Int: PropertyValueType {

    public static let type: PropertyType = .integer
}

extension Bool: PropertyValueType {

    public static let type: PropertyType = .bool
}

extension Double: PropertyValueType {

    public static let type: PropertyType = .double
}

extension String: PropertyValueType {

    public static let type: PropertyType = .string
}
