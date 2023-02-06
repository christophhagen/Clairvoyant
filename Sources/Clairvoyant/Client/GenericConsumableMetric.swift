import Foundation
import CBORCoding

public final class GenericConsumableMetric {

    let consumer: MetricConsumer

    public let id: MetricId

    public let dataType: MetricType

    private let timestampLength = 9

    private let decoder = CBORDecoder()

    init(consumer: MetricConsumer, id: MetricId, dataType: MetricType) {
        self.consumer = consumer
        self.id = id
        self.dataType = dataType
    }
    init(consumer: MetricConsumer, description: MetricDescription) {
        self.consumer = consumer
        self.id = description.id
        self.dataType = description.dataType
    }

    public func lastValueData() async throws -> (data: Data, timestamp: Date)? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        guard let (date, remaining) = decodeTimestamp(from: data) else {
            return nil
        }
        return (remaining, date)
    }

    public func lastValue() async throws -> (description: String, timestamp: Date)? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        return describe(data, type: dataType)
    }

    public func lastValue<T>(as: T.Type = T.self) async throws -> Timestamped<T>? where T: MetricValue {
        guard T.valueType == dataType else {
            throw MetricError.typeMismatch
        }
        return try await consumer.lastValue(for: id)
    }

    public func history(in range: ClosedRange<Date>) async throws -> [(description: String, timestamp: Date)] {
        let data = try await consumer.historyData(for: id, in: range)
        switch dataType {
        case .integer:
            return try decode(data, type: Int.self)
        case .double:
            return try decode(data, type: Double.self)
        case .boolean:
            return try decode(data, type: Bool.self)
        case .string:
            return try decode(data, type: String.self)
        case .data:
            return try decode(data, type: Data.self)
        case .enumeration:
            return try consumer.decode(logData: data).map { element in
                let value: UInt8 = try decoder.decode(from: element.data)
                return (description: "Enum(\(value))", timestamp: element.timestamp)
            }
        case .customType:
            return try consumer.decode(logData: data).map { ("\($0.data)", $0.timestamp) }
        case .serverStatus:
            return try decode(data, type: ServerStatus.self)
        }
    }

    func decode<T>(_ data: Data, type: T.Type = T.self) throws -> [(description: String, timestamp: Date)] where T: Decodable {
        try consumer.decode(logData: data).map { element in
            let value: T = try decoder.decode(from: element.data)
            return (description: "\(value)", timestamp: element.timestamp)
        }
    }

    private func describe(_ data: Data, type: MetricType) -> (description: String, timestamp: Date) {
        switch type {
        case .integer:
            return decode(Int.self, from: data)
        case .double:
            return decode(Double.self, from: data)
        case .boolean:
            return decode(Bool.self, from: data)
        case .string:
            return decode(String.self, from: data)
        case .enumeration:
            let a = decode(UInt8.self, from: data)
            return ("Enum(\(a.description))", a.timestamp)
        case .customType(let name):
            return (name, Date())
        case .data:
            return decode(Data.self, from: data)
        case .serverStatus:
            return decode(ServerStatus.self, from: data)
        }
    }

    private func decodeTimestamp(from data: Data) -> (timestamp: Date, remaining: Data)? {
        do {
            let timestampData = data.prefix(timestampLength)
            let timestamp = try decoder.decode(TimeInterval.self, from: timestampData)
            return (Date(timeIntervalSince1970: timestamp), data.advanced(by: timestampLength))

        } catch {
            print("Failed to decode timestamp of last value: \(error)")
            return nil
        }
    }

    private func decode<T>(_ type: T.Type, from data: Data) -> (description: String, timestamp: Date) where T: Codable {
        guard let (date, remaining) = decodeTimestamp(from: data) else {
            return ("Invalid timestamp", Date())
        }

        do {
            let value: T = try decoder.decode(from: remaining)
            return ("\(value)", date)
        } catch {
            print("Failed to decode last value: \(error)")
            return ("Decoding error", date)
        }
    }
}
