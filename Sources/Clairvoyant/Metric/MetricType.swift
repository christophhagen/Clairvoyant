import Foundation

public enum MetricType {
    case integer
    case double
    case boolean
    case string
    case data
    case enumeration
    case customType(named: String)

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
        default:
            self = .customType(named: stringDescription)
        }
    }
}
