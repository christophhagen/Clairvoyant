import Foundation

public enum ServerRoute {

    case getMetricList
    case lastValue(MetricIdHash)
    case allLastValues
    case extendedInfoList
    case metricHistory(MetricIdHash)
    case pushValueToMetric(MetricIdHash)

    public var rawValue: String {
        switch self {
        case .getMetricList: return "list"
        case .lastValue(let hash): return "last/\(hash)"
        case .allLastValues: return "last/all"
        case .extendedInfoList: return "list/extended"
        case .metricHistory(let hash): return "history/\(hash)"
        case .pushValueToMetric(let hash): return "push/\(hash)"
        }
    }

    public static var headerAccessToken = "token"
}

extension ServerRoute: Equatable {

    public static func == (lhs: ServerRoute, rhs: ServerRoute) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension ServerRoute: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension ServerRoute: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
