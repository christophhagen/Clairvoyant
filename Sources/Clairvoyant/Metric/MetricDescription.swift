import Foundation

public struct MetricDescription {

    let id: String

    let dataType: MetricType
}

extension MetricDescription: Encodable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(dataType.stringDescription)
    }
}

extension MetricDescription: Decodable {

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.id = try container.decode(String.self)
        self.dataType = .init(stringDescription: try container.decode(String.self))
    }
}
