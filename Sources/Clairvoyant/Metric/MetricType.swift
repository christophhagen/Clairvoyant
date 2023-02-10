import Foundation

public enum MetricType {
    case integer
    case double
    case boolean
    case string
    case data
    case enumeration
    case customType(named: String)
    case serverStatus
    //case httpStatus

    var stringDescription: String {
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
        case .enumeration:
            return "Enum"
        case .customType(let name):
            return name
        case .serverStatus:
            return "Status"
        //case .httpStatus:
        //    return "HTTP Status"
        }
    }

    init(stringDescription: String) {
        switch stringDescription {
        case "Int": self = .integer
        case "Double": self = .double
        case "Bool": self = .boolean
        case "String": self = .string
        case "Data": self = .data
        case "Enum": self = .enumeration
        case "Status": self = .serverStatus
        // case "HTTP Status": self = .httpStatus
        default:
            self = .customType(named: stringDescription)
        }
    }

    /// The Swift type associated with the metric type
    var type: (any MetricValue.Type)? {
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
        case .enumeration, .customType:
            return nil
        case .serverStatus:
            return ServerStatus.self
        }
    }
}

extension MetricType: Equatable {
    
}

extension MetricType: Codable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringDescription)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(stringDescription: try container.decode(String.self))
    }
}
