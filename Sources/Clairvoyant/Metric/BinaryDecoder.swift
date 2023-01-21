import Foundation

public protocol BinaryDecoder {

    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable

    var encodedTimestampLength: Int { get }
}
