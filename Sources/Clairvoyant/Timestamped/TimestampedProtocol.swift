import Foundation

/**
 A protocol adopted by timestamped values.
 */
public protocol TimestampedProtocol {
    
    /// The type of the value
    associatedtype Value
    
    /// The timestamp of the value
    var timestamp: Date { get }
    
    /// The value associated with the timestamp
    var value: Value { get }
}

extension TimestampedProtocol {
    
    /**
     Map the value to a different type while keeping the timestamp.
     - Parameter closure: The function to map the value to a different type.
     - Returns: The converted value timestamped with the original timestamp
     */
    public func mapValue<T>(_ closure: (Value) throws -> T) rethrows -> Timestamped<T> {
        .init(value: try closure(value), timestamp: timestamp)
    }
}

extension Sequence where Element: TimestampedProtocol {
    
    /**
     Map each element of the sequence to a new type using a transformation, while keeping the original timestamps.
     - Parameter transform: A mapping closure. `transform` accepts a value of this sequence as its parameter and returns a transformed value of the same or of a different type.
     - Returns: An array containing the transformed elements of this sequence.
     */
    public func mapValues<T>(_ transform: (Element.Value) throws -> T) rethrows -> [Timestamped<T>] {
        try map { try $0.mapValue(transform) }
    }
}
