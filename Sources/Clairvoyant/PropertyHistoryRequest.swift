import Foundation

public struct PropertyHistoryRequest: Codable {

    public let owner: String

    public let propertyId: UInt32

    public let range: ClosedRange<Date>
}
