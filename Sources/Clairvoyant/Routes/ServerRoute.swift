import Foundation

/**
 The routes existing on a Clairvoyant Vapor server.
 */
public enum ServerRoute {

    /// Get the info for a metric
    case getMetricInfo(MetricIdHash)

    /// Get a list of all metrics
    case getMetricList

    /// Get the last value of a specific metric
    case lastValue(MetricIdHash)

    /// Get last values of all metrics
    case allLastValues

    /// Get a list of all metrics with their last values
    case extendedInfoList

    /// Get past values of a specific metric
    case metricHistory(MetricIdHash)

    /// Update the value of a metric
    case pushValueToMetric(MetricIdHash)

    /// The full path of the route
    public var rawValue: String {
        switch self {
        case .getMetricInfo(let hash): return Prefix.getMetricInfo.appending(hash: hash)
        case .getMetricList: return Prefix.getMetricList.rawValue
        case .lastValue(let hash): return Prefix.lastValue.appending(hash: hash)
        case .allLastValues: return Prefix.allLastValues.rawValue
        case .extendedInfoList: return Prefix.extendedInfoList.rawValue
        case .metricHistory(let hash): return Prefix.metricHistory.appending(hash: hash)
        case .pushValueToMetric(let hash): return Prefix.pushValueToMetric.appending(hash: hash)
        }
    }

    /// The HTTP header key used for access tokens
    public static var headerAccessToken = "token"

    /// The start of the route, excluding hashes
    public var prefix: Prefix {
        switch self {
        case .getMetricInfo:
            return .getMetricInfo
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

    /// The prefix of a server route
    public enum Prefix: String {
        case getMetricInfo = "info"
        case getMetricList = "list"
        case lastValue = "last"
        case allLastValues = "last/all"
        case extendedInfoList = "list/extended"
        case metricHistory = "history"
        case pushValueToMetric = "push"

        /**
         Create a full server route by adding the hash of a metric.
         - Parameter hash: The metric id hash to add.
         - Returns: The full route
         */
        public func with(hash: MetricIdHash) -> ServerRoute {
            switch self {
            case .getMetricInfo: return .getMetricInfo(hash)
            case .getMetricList: return .getMetricList
            case .lastValue: return .lastValue(hash)
            case .allLastValues: return .allLastValues
            case .extendedInfoList: return .extendedInfoList
            case .metricHistory: return .metricHistory(hash)
            case .pushValueToMetric: return .pushValueToMetric(hash)
            }
        }

        /**
         Create a full server route by adding the hash of a metric.
         - Parameter hash: The metric id hash to add.
         - Returns: The full route as a string
         */
        public func appending(hash: MetricIdHash) -> String {
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
