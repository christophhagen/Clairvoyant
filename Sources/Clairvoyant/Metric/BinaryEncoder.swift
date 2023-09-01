import Foundation

/**
 An abstract specification of an encoder to use for metric storage and data transmission.
 */
public protocol BinaryEncoder {

    func encode<T>(_ value: T) throws -> Data where T: Encodable
}
