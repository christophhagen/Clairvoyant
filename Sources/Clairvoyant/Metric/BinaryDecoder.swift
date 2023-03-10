import Foundation

/**
 An abstract specification of a decoder to use for metric storage and data transmission.
 */
public protocol BinaryDecoder {

    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable

    var encodedTimestampLength: Int { get }
}
