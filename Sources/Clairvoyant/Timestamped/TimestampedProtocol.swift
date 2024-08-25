import Foundation

public protocol TimestampedProtocol {
    
    var timestamp: Date { get }
    
    associatedtype Value
    
    var value: Value { get }
}

extension TimestampedProtocol {
    
    public func mapValue<T>(_ closure: (Value) throws -> T) rethrows -> Timestamped<T> {
        .init(value: try closure(value), timestamp: timestamp)
    }
}

extension Sequence where Element: TimestampedProtocol {
    
    public func mapValues<T>(_ transform: (Element.Value) throws -> T) rethrows -> [Timestamped<T>] {
        try map { try $0.mapValue(transform) }
    }
}
