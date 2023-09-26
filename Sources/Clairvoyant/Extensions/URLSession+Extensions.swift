#if canImport(FoundationNetworking)
import Foundation
import FoundationNetworking

extension URLSession {

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result: Result<(response: URLResponse, data: Data), Error> = await withCheckedContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success((response!, data!)))
                }
            }
            task.resume()
        }
        switch result {
        case .failure(let error):
            throw error
        case .success(let result):
            return (result.data, result.response)
        }
    }
}

#endif
