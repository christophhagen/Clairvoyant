import Foundation
import CBORCoding
#if canImport(Vapor)
import Vapor

private let encoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970)

extension Application {

    @discardableResult
    func post(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> Data) -> Route {
        wrappingPost(subPath, path, use: closure)
    }

    @discardableResult
    func post<T>(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> T) -> Route where T: Encodable {
        wrappingPost(subPath, path) { request in
            let value = try await closure(request)
            return try encoder.encode(value)
        }
    }

    @discardableResult
    func post(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> Void) -> Route {
        wrappingPost(subPath, path) { request in
            try await closure(request)
            return Data()
        }
    }

    private func wrappingPost(_ subPath: String, _ path: [PathComponent], use closure: @escaping (Request) async throws -> Data) -> Route {
        post([.constant(subPath)] + path)  { request -> Response in
            do {
                let data = try await closure(request)
                return .init(status: .ok, body: .init(data: data))
            } catch let error as MetricError {
                return Response(status: error.status)
            } catch {
                throw error
            }
        }
    }
}

#endif
