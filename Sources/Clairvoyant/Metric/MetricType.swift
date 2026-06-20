import Foundation

public enum MetricType: RawRepresentable {
    
    /// A Swift `Int` type
    case integer
    
    /// A Swift `Double` type
    case double
    
    /// A Swift `Bool` type
    case boolean
    
    /// A Swift `String` type
    case string
    
    /// A Swift `Data` type
    case data
    
    /// A Swift `Date` type
    case date

    /// A Swift `ServerStatus` type
    case serverStatus
    
    /// A Swift `HTTPStatus` type
    case httpStatus
    
    /// A `SemanticVersion` type
    case semanticVersion
    
    /// A custom type specific to the application
    case customType(named: String)
    
    public var rawValue: String {
        switch self {
        case .integer:
            return "Int"
        case .double:
            return "Double"
        case .boolean:
            return "Bool"
        case .string:
            return "String"
        case .data:
            return "Data"
        case .date:
            return "Date"
        case .serverStatus:
            return "Status"
        case .httpStatus:
            return "HTTP Status"
        case .semanticVersion:
            return "SemanticVersion"
        case .customType(let name):
            return name
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "Int": self = .integer
        case "Double": self = .double
        case "Bool": self = .boolean
        case "String": self = .string
        case "Data": self = .data
        case "Date": self = .date
        case "Status": self = .serverStatus
        case "HTTP Status": self = .httpStatus
        case "SemanticVersion": self = .semanticVersion
        default:
            self = .customType(named: rawValue)
        }
    }

    /// The Swift type associated with the metric type
    public var type: (any MetricValue.Type)? {
        switch self {
        case .integer:
            return Int.self
        case .double:
            return Double.self
        case .boolean:
            return Bool.self
        case .string:
            return String.self
        case .data:
            return Data.self
        case .date:
            return Date.self
        case .serverStatus:
            return ServerStatus.self
        case .httpStatus:
            return HTTPStatusCode.self
        case .semanticVersion:
            return SemanticVersion.self
        case .customType:
            return nil
        }
    }
}

extension MetricType: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}

extension MetricType: Equatable {
    
}

extension MetricType: Codable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }
}

extension MetricType: ExpressibleByStringLiteral {
    
    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

extension MetricType: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}
