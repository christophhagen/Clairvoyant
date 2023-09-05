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
        case .getMetricList: return Prefix.getMetricList.rawValue
        case .lastValue(let hash): return Prefix.lastValue.appending(hash: hash)
        case .allLastValues: return Prefix.allLastValues.rawValue
        case .extendedInfoList: return Prefix.extendedInfoList.rawValue
        case .metricHistory(let hash): return Prefix.metricHistory.appending(hash: hash)
        case .pushValueToMetric(let hash): return Prefix.pushValueToMetric.appending(hash: hash)
        }
    }

    public static var headerAccessToken = "token"

    public var prefix: Prefix {
        switch self {
        case .getMetricList:
            return .getMetricList
        case .lastValue:
            return .lastValue
        case .allLastValues:
            return .allLastValues
        case .extendedInfoList:
            return .extendedInfoList
        case .metricHistory:
            return .metricHistory
        case .pushValueToMetric:
            return .pushValueToMetric
        }
    }

    public enum Prefix: String {
        case getMetricList = "list"
        case lastValue = "last"
        case allLastValues = "last/all"
        case extendedInfoList = "list/extended"
        case metricHistory = "history"
        case pushValueToMetric = "push"

        func with(hash: MetricIdHash) -> ServerRoute {
            switch self {
            case .getMetricList: return .getMetricList
            case .lastValue: return .lastValue(hash)
            case .allLastValues: return .allLastValues
            case .extendedInfoList: return .extendedInfoList
            case .metricHistory: return .metricHistory(hash)
            case .pushValueToMetric: return .pushValueToMetric(hash)
            }
        }

        func appending(hash: MetricIdHash) -> String {
            return rawValue + "/" + hash
        }
    }
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
