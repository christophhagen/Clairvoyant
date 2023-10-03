import Foundation

public enum MetricType: RawRepresentable {
    case integer
    case double
    case boolean
    case string
    case data
    case customType(named: String)
    case serverStatus
    case httpStatus
    case semanticVersion

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
        case .customType(let name):
            return name
        case .serverStatus:
            return "Status"
        case .httpStatus:
            return "HTTP Status"
        case .semanticVersion:
            return "SemanticVersion"
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "Int": self = .integer
        case "Double": self = .double
        case "Bool": self = .boolean
        case "String": self = .string
        case "Data": self = .data
        case "Status": self = .serverStatus
        case "HTTP Status": self = .httpStatus
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
        case .customType:
            return nil
        case .serverStatus:
            return ServerStatus.self
        case .httpStatus:
            return HTTPStatusCode.self
        case .semanticVersion:
            return SemanticVersion.self
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
