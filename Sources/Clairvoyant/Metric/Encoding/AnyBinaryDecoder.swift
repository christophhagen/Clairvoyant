import Foundation

/**
 An abstract specification of a decoder to use for metric storage and data transmission.
 */
public protocol AnyBinaryDecoder {

    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

public extension AnyBinaryDecoder {

    func decode<T>(from data: Data) throws -> T where T: Decodable {
        try decode(T.self, from: data)
    }
}
