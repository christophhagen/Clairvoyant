import Foundation

public struct PropertyHistoryRequest {

    public let owner: String

    public let propertyId: UInt32

    public let range: ClosedRange<Date>

    public init(owner: String, propertyId: UInt32, range: ClosedRange<Date>) {
        self.owner = owner
        self.propertyId = propertyId
        self.range = range
    }
}

extension PropertyHistoryRequest: Codable {

}
