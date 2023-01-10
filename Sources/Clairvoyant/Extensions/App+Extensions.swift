import Foundation
import Vapor
import CBORCoding

private let encoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970)

extension Application {

    @discardableResult
    func post(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> Data) -> Route {
        post([.constant(subPath)] + path) { request -> Response in
            let data = try await closure(request)
            return .init(status: .ok, body: .init(data: data))
        }
    }

    @discardableResult
    func post<T>(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> T) -> Route where T: Encodable {
        post([.constant(subPath)] + path) { request -> Response in
            let value = try await closure(request)
            let data = try encoder.encode(value)
            return .init(status: .ok, body: .init(data: data))
        }
    }

    @discardableResult
    func post(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> Void) -> Route {
        post([.constant(subPath)] + path) { request -> Response in
            try await closure(request)
            return .init(status: .ok)
        }
    }
}

