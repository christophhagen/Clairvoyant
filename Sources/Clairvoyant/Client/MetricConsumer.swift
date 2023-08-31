import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor MetricConsumer {

    private(set) public var serverUrl: URL

    private(set) public var accessProvider: MetricRequestAccessProvider

    private(set) public var session: URLSession

    public let decoder: BinaryDecoder

    public let encoder: BinaryEncoder

    public init(
        url: URL,
        accessProvider: MetricRequestAccessProvider,
        session: URLSession = .shared,
        encoder: BinaryEncoder,
        decoder: BinaryDecoder) {

        self.serverUrl = url
        self.accessProvider = accessProvider
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public func set(serverUrl: URL) {
        self.serverUrl = serverUrl
    }

    public func set(accessProvider: MetricRequestAccessProvider) {
        self.accessProvider = accessProvider
    }

    public func set(session: URLSession) {
        self.session = session
    }

    public func list() async throws -> [MetricDescription] {
        let data = try await post(path: "list")
        return try decode(from: data)
    }

    public func metric<T>(id: MetricId, name: String? = nil, description: String? = nil) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, id: id, name: name, description: description)
    }

    public func metric(from description: MetricDescription) -> GenericConsumableMetric {
        .init(consumer: self, description: description, decoder: decoder)
    }

    func lastValueData(for metric: MetricId) async throws -> Data? {
        do {
            return try await post(path: "last/\(metric.hashed())")
        } catch MetricError.noValueAvailable {
            return nil
        }
    }

    public func lastValue<T>(for metric: MetricId, type: T.Type = T.self) async throws -> Timestamped<T>? where T: MetricValue {
        guard let data = try await lastValueData(for: metric) else {
            return nil
        }
        do {
            return try decoder.decode(Timestamped<T>.self, from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    func historyData(for metric: MetricId, in range: ClosedRange<Date>) async throws -> Data {
        let request = MetricHistoryRequest(range)
        let body = try encode(request)
        return try await post(path: "history/\(metric.hashed())", body: body)
    }

    public func history<T>(for metric: MetricId, in range: ClosedRange<Date>, type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let data = try await historyData(for: metric, in: range)
        return try decode(from: data)
    }

    private func post(path: String, body: Data? = nil) async throws -> Data {
        let url = serverUrl.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        accessProvider.addAccessDataToMetricRequest(&request)
        do {
            let (data, response) = try await urlSessionData(session, for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MetricError.requestFailed
            }
            if response.statusCode == 200 {
                return data
            }
            if let metricError = MetricError(statusCode: response.statusCode) {
                throw metricError
            }
            throw MetricError.requestFailed
        } catch let error as MetricError {
            throw error
        } catch {
            throw MetricError.requestFailed
        }
    }

    private func decode<T>(_ type: T.Type = T.self, from data: Data) throws -> T where T: Decodable {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    private func encode<T>(_ value: T) throws -> Data where T: Encodable {
        do {
            return try encoder.encode(value)
        } catch {
            throw MetricError.failedToEncode
        }
    }
}
