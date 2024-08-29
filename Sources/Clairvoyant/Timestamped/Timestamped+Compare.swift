import Foundation

extension TimestampedProtocol where Value: Equatable {
    
    func isDifferentAndNewer(than other: Self) -> Bool {
        value != other.value && timestamp > other.timestamp
    }
}
