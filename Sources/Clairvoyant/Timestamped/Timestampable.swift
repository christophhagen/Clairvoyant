import Foundation

/**
 A type that can be converted to a timestamped value.
 */
public protocol Timestampable {

}

extension Timestampable {

    /**
     Create a timestamped value.
     - Parameter timestamp: The timestamp to add to the value, default to the current time.
     - Returns: The timestamped value
     */
    public func timestamped(with timestamp: Date = Date()) -> Timestamped<Self> {
        .init(value: self, timestamp: timestamp)
    }
}
