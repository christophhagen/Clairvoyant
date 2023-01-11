import Foundation

public struct PropertyId: Codable, Hashable {

    public let owner: String

    public let uniqueId: UInt32

    enum CodingKeys: Int, CodingKey {
        case owner = 1
        case uniqueId = 2
    }

    public init(owner: String, uniqueId: UInt32) {
        self.owner = owner
        self.uniqueId = uniqueId
    }
}
