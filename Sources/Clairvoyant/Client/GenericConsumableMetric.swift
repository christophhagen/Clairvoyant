import Foundation

extension ConsumableMetric: GenericConsumableMetric {

    public func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R : MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        guard let value = try await self.lastValue() else {
            return nil
        }
        guard let converted = value as? Timestamped<R>? else {
            throw MetricError.typeMismatch
        }
        return converted
    }

    public func history<R>(in range: ClosedRange<Date>, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue {
        guard T.valueType == R.valueType else {
            throw MetricError.typeMismatch
        }
        let values = try await self.history(in: range)
        return try values.map {
            guard let result = $0 as? Timestamped<R> else {
                throw MetricError.typeMismatch
            }
            return result
        }
    }

    public func lastValueData() async throws -> Data? {
        guard let data = try await consumer.lastValueData(for: id) else {
            return nil
        }
        return data
    }

    public func lastValueDescription() async throws -> Timestamped<String>? {
        guard let value = try await lastValue() else {
            return nil
        }
        return value.mapValue { "\($0)" }
    }
}

extension GenericConsumableMetric {

    public var id: MetricId {
        description.id
    }

    public var dataType: MetricType {
        description.dataType
    }

    public var name: String? {
        description.name
    }
}

public protocol GenericConsumableMetric {

    var consumer: MetricConsumer { get }

    var description: MetricDescription { get }

    func lastValueData() async throws -> Data?

    func lastValueDescription() async throws -> Timestamped<String>?

    func lastValue<R>(as type: R.Type) async throws -> Timestamped<R>? where R: MetricValue

    func history<R>(in range: ClosedRange<Date>, as type: R.Type) async throws -> [Timestamped<R>] where R: MetricValue
}

/*

    func history(in range: ClosedRange<Date>) async throws -> [(description: String, timestamp: Date)] {
        let data = try await consumer.historyData(for: id, in: range)
        switch dataType {
        case .integer:
            return try decodeTimestampedArray(data, type: Int.self)
        case .double:
            return try decodeTimestampedArray(data, type: Double.self)
        case .boolean:
            return try decodeTimestampedArray(data, type: Bool.self)
        case .string:
            return try decodeTimestampedArray(data, type: String.self)
        case .data:
            return try decodeTimestampedArray(data, type: Data.self)
        case .enumeration:
            return try decodeTimestampedArray(data, type: UInt8.self).map { element in
                return (description: "Enum(\(element.description))", timestamp: element.timestamp)
            }
        case .customType(let name):
            return try decoder.decode([AnyTimestamped].self, from: data).map { element in
                (description: name, timestamp: element.timestamp)
            }
        case .serverStatus:
            return try decodeTimestampedArray(data, type: ServerStatus.self)
        }
    }

    private func decodeTimestampedArray<T>(_ data: Data, type: T.Type = T.self) throws -> [(description: String, timestamp: Date)] where T: Decodable {
        try decoder.decode([Timestamped<T>].self, from: data).map { element in
            (description: "\(element.value)", timestamp: element.timestamp)
        }
    }

    private func describe(_ data: Data, type: MetricType) -> (description: String, timestamp: Date) {
        switch type {
        case .integer:
            return decodeTimestamped(Int.self, from: data)
        case .double:
            return decodeTimestamped(Double.self, from: data)
        case .boolean:
            return decodeTimestamped(Bool.self, from: data)
        case .string:
            return decodeTimestamped(String.self, from: data)
        case .enumeration:
            let value = decodeTimestamped(UInt8.self, from: data)
            return ("Enum(\(value.description))", value.timestamp)
        case .customType(let name):
            guard let value: AnyTimestamped = try? decode(from: data) else {
                return ("Decoding error", Date())
            }
            return (name, value.timestamp)
        case .data:
            return decodeTimestamped(Data.self, from: data)
        case .serverStatus:
            return decodeTimestamped(ServerStatus.self, from: data)
        }
    }

    private func decodeTimestamped<T>(_ type: T.Type, from data: Data) -> (description: String, timestamp: Date) where T: Codable {
        do {
            let value: Timestamped<T> = try decoder.decode(from: data)
            return ("\(value)", value.timestamp)
        } catch {
            print("Failed to decode last value: \(error)")
            return ("Decoding error", Date())
        }
    }

    private func decode<T>(from data: Data) throws -> T where T : Decodable {
        do {
            return try decoder.decode(from: data)
        } catch {
            print("Failed to decode \(data): \(error)")
            throw error
        }
    }
}
*/
