import Foundation

/**
 A description of a metric published by a server, including the last value data
 */
public struct ExtendedMetricInfo {

    /// The unique if of the metric
    public let info: MetricDescription

    /// The data of the last value
    public let lastValueData: Data?

    public init(info: MetricDescription, lastValueData: Data? = nil) {
        self.info = info
        self.lastValueData = lastValueData
    }
}

extension ExtendedMetricInfo: Codable {

    enum CodingKeys: Int, CodingKey {
        case info = 1
        case lastValueData = 2
    }
}

extension ExtendedMetricInfo: Equatable {

    public static func == (_ lhs: ExtendedMetricInfo, _ rhs: ExtendedMetricInfo) -> Bool {
        lhs.info.id == rhs.info.id
    }
}

extension ExtendedMetricInfo: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(info.id)
    }
}
