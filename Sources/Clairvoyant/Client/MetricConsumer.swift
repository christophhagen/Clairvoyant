import Foundation
import CBORCoding

public final class MetricConsumer {

    public let serverUrl: URL

    let accessProvider: MetricRequestAccessProvider

    public let session: URLSession

    let decoder: CBORDecoder

    let encoder: CBOREncoder

    public init(url: URL, accessProvider: MetricRequestAccessProvider, session: URLSession = .shared) {
        self.serverUrl = url
        self.accessProvider = accessProvider
        self.session = session
        self.decoder = .init()
        self.encoder = .init(dateEncodingStrategy: .secondsSince1970)
    }

    public func list() async throws -> [MetricDescription] {
        let data = try await post(path: "list")
        return try decode(from: data)
    }

    public func metric<T>(id: MetricId) -> ConsumableMetric<T> where T: MetricValue {
        .init(consumer: self, id: id)
    }

    public func metric(from description: MetricDescription) -> GenericConsumableMetric {
        .init(consumer: self, description: description)
    }

    func lastValueData(for metric: MetricId) async throws -> Data? {
        do {
            return try await post(path: "last/\(metric)")
        } catch MetricError.noValueAvailable {
            return nil
        }
    }

    public func lastValue<T>(for metric: MetricId, type: T.Type = T.self) async throws -> Timestamped<T>? where T: MetricValue {
        guard let data = try await lastValueData(for: metric) else {
            return nil
        }
        return try decode(Timestamped<T>.self, from: data)
    }

    func historyData(for metric: MetricId, in range: ClosedRange<Date>) async throws -> Data {
        let body = try encode(range)
        return try await post(path: "history/\(metric)", body: body)
    }

    public func history<T>(for metric: MetricId, in range: ClosedRange<Date>, type: T.Type = T.self) async throws -> [Timestamped<T>] where T: MetricValue {
        let data = try await historyData(for: metric, in: range)
        return try decode(logData: data)
    }

    private func post(path: String, body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        let url = serverUrl.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
        accessProvider.addAccessDataToMetricRequest(&request)
        do {
            let (data, response) = try await session.data(for: request)
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
        } catch {
            throw error
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

    /// The length of the binary data of a timestamp encoded in CBOR
    private let encodedTimestampLength = 9

    func decode<T>(logData data: Data) throws -> [Timestamped<T>] where T: MetricValue {
        try decode(logData: data).map {
            do {
                let value: T = try decoder.decode(from: $0.data)
                return .init(timestamp: $0.timestamp, value: value)
            } catch {
                throw MetricError.failedToDecode
            }
        }
    }

    func decode(logData data: Data) throws -> [(timestamp: Date, data: Data)] {
        var result = [(timestamp: Date, data: Data)]()
        var index = data.startIndex
        while index < data.endIndex {
            guard index + 2 <= data.endIndex else {
                throw MetricError.failedToDecode
            }
            let byteCountData = data[index..<index+2]
            guard let byteCountRaw = UInt16(fromData: byteCountData) else {
                throw MetricError.failedToDecode
            }
            let byteCount = Int(byteCountRaw)
            index += 2
            guard index + byteCount <= data.endIndex else {
                throw MetricError.failedToDecode
            }

            guard byteCount >= encodedTimestampLength else {
                throw MetricError.failedToDecode
            }
            let timestamp: Date
            do {
                let timestampData = data[index..<index+encodedTimestampLength]
                let timestampInterval: TimeInterval = try decoder.decode(from: timestampData)
                timestamp = .init(timeIntervalSince1970: timestampInterval)
            } catch {
                throw MetricError.logFileCorrupted
            }

            let valueData = data[index+encodedTimestampLength..<index+byteCount]
            index += byteCount
            result.append((timestamp, valueData))
        }
        return result
    }
}
