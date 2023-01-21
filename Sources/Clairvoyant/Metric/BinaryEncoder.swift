import Foundation

public protocol BinaryEncoder {

    func encode<T>(_ value: T) throws -> Data where T: Encodable

    var encodedTimestampLength: Int { get }
}
