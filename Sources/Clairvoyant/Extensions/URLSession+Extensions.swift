import Foundation


#if canImport(FoundationNetworking)
extension URLSession {

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result: Result<(Data, URLResponse), Error> = await withCheckedContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success((data!, response!)))
                }
            }
            task.resume()
        }
        switch result {
        case .failure(let error):
            throw error
        case .success(let result):
            return result
        }
    }
}
#endif
