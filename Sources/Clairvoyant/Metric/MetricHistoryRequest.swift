import Foundation

public struct MetricHistoryRequest {

    public let start: Date

    public let end: Date

    public let limit: Int?

    public init(_ range: ClosedRange<Date>, limit: Int? = nil) {
        self.start = range.lowerBound
        self.end = range.upperBound
        self.limit = limit
    }

    public init(start: Date, end: Date, limit: Int? = nil) {
        self.start = start
        self.end = end
        self.limit = limit
    }
}

extension MetricHistoryRequest: Codable {

    enum CodingKeys: Int, CodingKey {
        case start = 1
        case end = 2
        case limit = 3
    }
}
