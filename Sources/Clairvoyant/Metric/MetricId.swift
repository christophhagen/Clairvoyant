import Foundation

public struct MetricId {
    
    public let id: String
    
    public let group: String
    
    public init(id: String, group: String) {
        self.id = id
        self.group = group
    }
}

extension MetricId: Equatable {
    
}

extension MetricId: Hashable {
    
}

extension MetricId: Codable {
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.group = try container.decode(String.self, forKey: .group)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(group, forKey: .group)
    }
    
    enum CodingKeys: Int, CodingKey {
        case id = 1
        case group = 2
    }
}

extension MetricId: Comparable {
    
    public static func < (lhs: MetricId, rhs: MetricId) -> Bool {
        guard lhs.group == rhs.group else {
            return lhs.group < rhs.group
        }
        return lhs.id < rhs.id
    }
}

extension MetricId: CustomStringConvertible {

    public var description: String {
        "(\(group):\(id))"
    }
}
