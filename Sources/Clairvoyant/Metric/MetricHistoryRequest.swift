import Foundation

public struct MetricHistoryRequest {

    public let id: String

    public let range: ClosedRange<Date>

    public init(id: String, range: ClosedRange<Date>) {
        self.id = id
        self.range = range
    }
}

extension MetricHistoryRequest: Codable {

    enum CodingKeys: Int, CodingKey {
        case id = 1
        case range = 2
    }
}
