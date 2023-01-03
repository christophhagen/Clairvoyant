import Foundation

public struct PropertyId: Codable, Hashable {

    public let name: String

    public let uniqueId: UInt32

    enum CodingKeys: Int, CodingKey {
        case name = 1
        case uniqueId = 2
    }

    public init(name: String, uniqueId: UInt32) {
        self.name = name
        self.uniqueId = uniqueId
    }
}
