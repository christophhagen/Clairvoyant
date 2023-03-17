import Foundation
import Clairvoyant
import Vapor

extension Request {

    func token() throws -> Data {
        guard let string = headers.first(name: "token") else {
            throw Abort(.badRequest)
        }
        guard let data = Data(base64Encoded: string) else {
            throw Abort(.badRequest)
        }
        return data
    }

    func decodeBody<T>(as type: T.Type = T.self, using decoder: BinaryDecoder) throws -> T where T: Decodable {
        guard let data = body.data?.all() else {
            throw Abort(.badRequest)
        }
        do {
            return try decoder.decode(from: data)
        } catch {
            throw Abort(.badRequest)
        }
    }
}
