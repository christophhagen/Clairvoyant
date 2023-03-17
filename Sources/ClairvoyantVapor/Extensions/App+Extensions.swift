import Foundation
import Vapor
import Clairvoyant

extension Application {

    @discardableResult
    func post(_ subPath: String, _ path: PathComponent..., use closure: @escaping (Request) async throws -> Data) -> Route {
        wrappingPost(subPath, path, use: closure)
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
