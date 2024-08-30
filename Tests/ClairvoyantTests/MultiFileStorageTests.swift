import XCTest
import Clairvoyant
import MetricFileStorage

typealias Storage = MultiFileStorage

final class MultiFileStorageTests: XCTestCase {

    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false

        do {
            try databasePath.removeIfPresent()
        } catch {
            print("Failed to remove database file: \(error)")
        }
    }

    private var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    private var databasePath: URL {
        temporaryDirectory.appendingPathComponent("db", isDirectory: true)
    }

    private func database() throws -> Storage {
        try Storage(
            logFolder: databasePath,
            logMetricId: "log",
            logMetricGroup: "test",
            encoderCreator: JSONEncoder.init,
            decoderCreator: JSONDecoder.init)
    }

    func testCreateDatabase() throws {
        _ = try database()
    }

    private func metricAndStorage() throws -> (metric: Metric<Int>, storage: Storage) {
        let storage = try database()
        let metric: Metric<Int> = try storage.metric(id: "metric", group: "test")
        return (metric, storage)
    }

    func testCreateMetric() throws {
        let (metric, storage) = try metricAndStorage()
        let metrics = storage.metrics()
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics[0], metric.info)
    }

    func testDeleteMetric() throws {
        let (metric, storage) = try metricAndStorage()

        try storage.delete(metric)

        let metrics = storage.metrics()
        XCTAssertEqual(metrics.count, 0)
    }

    func testStoreValue() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value = 123
        try metric.update(value)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
    }

    func testStoreValueWithTimestamp() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value = 123
        let timestamp = Date.now
        let updated = try metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testStoreMultipleValues() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value1 = 123
        let timestamp1 = Date.now
        let updated1 = try metric.update(value1, timestamp: timestamp1)
        XCTAssertTrue(updated1)

        let current1 = try metric.currentValue()
        XCTAssertNotNil(current1)
        XCTAssertEqual(current1!.value, value1)
        XCTAssertEqual(current1!.timestamp, timestamp1)

        let value2 = 234
        let timestamp2 = timestamp1.addingTimeInterval(1)
        let updated2 = try metric.update(value2, timestamp: timestamp2)
        XCTAssertTrue(updated2)

        let current2 = try metric.currentValue()
        XCTAssertNotNil(current2)
        XCTAssertEqual(current2!.value, value2)
        XCTAssertEqual(current2!.timestamp, timestamp2)

        let value3 = 345
        let timestamp3 = timestamp2.addingTimeInterval(1)
        let updated3 = try metric.update(value3, timestamp: timestamp3)
        XCTAssertTrue(updated3)

        let current3 = try metric.currentValue()
        XCTAssertNotNil(current3)
        XCTAssertEqual(current3!.value, value3)
        XCTAssertEqual(current3!.timestamp, timestamp3)
    }

    func testStoreSameValue() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value = 123
        let timestamp = Date.now
        let updated = try metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        // Update again with newer timestamp
        let updatedAgain = try metric.update(value, timestamp: timestamp.addingTimeInterval(1))
        XCTAssertFalse(updatedAgain)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testStoreOldValue() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value = 123
        let timestamp = Date.now
        let updated = try metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        // Update again with older timestamp
        let updatedAgain = try metric.update(234, timestamp: timestamp.addingTimeInterval(-1))
        XCTAssertFalse(updatedAgain)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testComplexValue() throws {
        struct Value: Codable, MetricValue {
            static var valueType: MetricType = "Value"
            let id: Int
            let name: String
        }
        let storage = try database()
        let metric: Metric<Value> = try storage.metric(id: "metric", group: "test")

        let value = Value(id: 123, name: "123")
        let timestamp = Date.now
        let updated = try metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)
    }

    func testStoreBatch() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values: [Timestamped<Int>] = [
            .init(value: 123, timestamp: date),
            .init(value: 234, timestamp: date.addingTimeInterval(1)),
            .init(value: 345, timestamp: date.addingTimeInterval(2))
        ]
        try metric.update(values)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values.last!.value)
        XCTAssertEqual(current!.timestamp, values.last!.timestamp)
    }

    func testStoreOutOfOrderBatch() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values: [Timestamped<Int>] = [
            .init(value: 345, timestamp: date.addingTimeInterval(2)),
            .init(value: 123, timestamp: date),
            .init(value: 234, timestamp: date.addingTimeInterval(1)),
        ]
        try metric.update(values)

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values.first!.value)
        XCTAssertEqual(current!.timestamp, values.first!.timestamp)
    }

    func testStorePartiallyOutdatedBatch() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let value = 345
        let date = Date.now

        let updated = try metric.update(value, timestamp: date.addingTimeInterval(1))
        XCTAssertTrue(updated)

        let values: [Timestamped<Int>] = [
            .init(value: 123, timestamp: date.addingTimeInterval(0)), // Not saved due to timestamp
            .init(value: 234, timestamp: date.addingTimeInterval(1)), // Not saved due to timestamp
            .init(value: 345, timestamp: date.addingTimeInterval(2)), // Not saved due to same value
            .init(value: 456, timestamp: date.addingTimeInterval(3)), // Saved
            .init(value: 456, timestamp: date.addingTimeInterval(4)), // Not saved due to same value
            .init(value: 678, timestamp: date.addingTimeInterval(4)), // Not saved due to timestamp
            .init(value: 567, timestamp: date.addingTimeInterval(5)), // Saved
            .init(value: 567, timestamp: date.addingTimeInterval(6)), // Not saved due to same value
        ]
        try metric.update(values)

        let history = try metric.history()
        for item in history {
            print("\(item.timestamp.timeIntervalSinceReferenceDate): \(item.value)")
        }

        let current = try metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values[6].value)
        XCTAssertEqual(current!.timestamp, values[6].timestamp)
    }

    func testFullHistory() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric.update(values)

        let stored = try metric.history()
        XCTAssertEqual(stored, values)
    }

    func testReverseHistory() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric.update(values)

        let stored = try metric.history(from: .distantFuture, to: .distantPast)
        XCTAssertEqual(stored, values.reversed())
    }

    func testPartialHistory() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric.update(values)

        let stored = try metric.history(
            from: date.addingTimeInterval(15.5),
            to: date.addingTimeInterval(35.5))
        XCTAssertEqual(stored, Array(values[15...34]))
    }

    func testDeleteAllValues() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric.update(values)

        try metric.deleteHistory()

        let stored = try metric.history()
        let current = try metric.currentValue()
        XCTAssertEqual(stored.count, 0)
        XCTAssertNil(current)
    }

    func testDeleteSomeValues() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        let start = date.addingTimeInterval(15.5)
        let end = date.addingTimeInterval(35.5)
        try metric.update(values)

        try metric.deleteHistory(from: start, to: end)

        let deleted = try metric.history(from: start, to: end)
        XCTAssertEqual(deleted.count, 0)

        let remaining = try metric.history()
        XCTAssertEqual(remaining, Array(values[...14] + values[35...]))
    }

    func testDeletesMetricDataAfterMetricDeletion() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1) // To keep `storage` from being deallocated

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric.update(values)

        try storage.delete(metric)
        XCTAssertEqual(storage.metrics().count, 0)
    }

    func testCreateMultipleMetrics() throws {
        let (_, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1)

        let id = MetricId(id: "m2", group: "test")
        let name = "Metric 2"
        let description = "Metric 2 Description"
        let metric2 = try storage.metric(id: id, name: name, description: description, type: String.self)
        XCTAssertEqual(storage.metrics().count, 2)
        XCTAssertEqual(metric2.id, id)
        XCTAssertEqual(metric2.name, name)
        XCTAssertEqual(metric2.description, description)

        // Create new handle to check that info is correctly loaded
        let metric3 = try storage.metric(id: id, type: String.self)
        XCTAssertEqual(storage.metrics().count, 2)
        XCTAssertEqual(metric3.id, id)
        XCTAssertEqual(metric3.name, name)
        XCTAssertEqual(metric3.description, description)
    }

    func testUpdateMetricInfo() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1)

        let name = "Metric 2"
        let description = "Metric 2 Description"
        let metric2 = try storage.metric(id: metric.id, name: name, description: description, type: Int.self)
        XCTAssertEqual(storage.metrics().count, 1)
        XCTAssertEqual(metric2.id, metric.id)
        XCTAssertEqual(metric2.name, name)
        XCTAssertEqual(metric2.description, description)

        // Old handle still has old information
        XCTAssertNotEqual(metric.name, name)
        XCTAssertNotEqual(metric.description, description)

        // Create new handle to check that info is correctly loaded
        let metric3 = try storage.metric(id: metric.id, type: Int.self)
        XCTAssertEqual(storage.metrics().count, 1)
        XCTAssertEqual(metric3.id, metric.id)
        XCTAssertEqual(metric3.name, name)
        XCTAssertEqual(metric3.description, description)
    }

    func testHandleWithInvalidType() throws {
        let (metric, storage) = try metricAndStorage()
        XCTAssertEqual(storage.metrics().count, 1)

        do {
            _ = try storage.metric(id: metric.id, type: String.self)
        } catch MetricError.typeMismatch {

        } catch {
            XCTFail("Should not be able to create metric with same ids and different types")
        }
    }

    func testStoreDataInMultipleMetrics() throws {
        let (metric, storage) = try metricAndStorage()
        let metric2 = try storage.metric(id: "2", group: "test", type: Int.self)
        XCTAssertEqual(storage.metrics().count, 2)

        try metric.update(1)
        XCTAssertEqual(try metric.currentValue()?.value, 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric), 1)
        XCTAssertNil(try metric2.currentValue())
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 0)

        try metric2.update(2)
        XCTAssertEqual(try metric.currentValue()?.value, 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric), 1)
        XCTAssertEqual(try metric2.currentValue()?.value, 2)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 1)

        try metric.update(3)
        XCTAssertEqual(try metric.currentValue()?.value, 3)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric), 2)
        XCTAssertEqual(try metric2.currentValue()?.value, 2)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 1)

        try metric2.update(4)
        XCTAssertEqual(try metric.currentValue()?.value, 3)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric), 2)
        XCTAssertEqual(try metric2.currentValue()?.value, 4)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 2)
    }

    func testDeleteOneOfMultipleMetrics() throws {
        let (metric1, storage) = try metricAndStorage()
        let metric2 = try storage.metric(id: "2", group: "test", type: Int.self)
        let metric3 = try storage.metric(id: "3", group: "test", type: Int.self)
        XCTAssertEqual(storage.metrics().count, 3)

        try metric1.update(1)
        try metric2.update(2)
        try metric3.update(3)

        XCTAssertEqual(try metric1.currentValue()?.value, 1)
        XCTAssertEqual(try metric2.currentValue()?.value, 2)
        XCTAssertEqual(try metric3.currentValue()?.value, 3)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric3), 1)

        try storage.delete(metric2)

        XCTAssertEqual(try metric1.currentValue()?.value, 1)
        XCTAssertEqual(try metric3.currentValue()?.value, 3)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric3), 1)

        func catchError<T>(_ msg: String, _ block: @autoclosure () throws -> T) {
            do {
                _ = try block()
            } catch MetricError.notFound {

            } catch {
                XCTFail("Should not be able to \(msg)")
            }
        }
        catchError("get current value of deleted metric", try metric2.currentValue())

        catchError("update value of deleted metric", try metric2.update(1))

        catchError("get history of deleted metric", try metric2.history())

        catchError("delete already deleted metric", try storage.delete(metric2))
    }

    func testDeleteHistoryOfOneMetric() throws {
        let (metric1, storage) = try metricAndStorage()
        let metric2 = try storage.metric(id: "2", group: "test", type: Int.self)
        let metric3 = try storage.metric(id: "3", group: "test", type: Int.self)
        XCTAssertEqual(storage.metrics().count, 3)

        try metric1.update(1)
        try metric2.update(2)
        try metric3.update(3)

        XCTAssertEqual(try metric1.currentValue()?.value, 1)
        XCTAssertEqual(try metric2.currentValue()?.value, 2)
        XCTAssertEqual(try metric3.currentValue()?.value, 3)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric3), 1)

        try metric2.deleteHistory()

        XCTAssertNil(try metric2.currentValue())

        XCTAssertEqual(try metric1.currentValue()?.value, 1)
        XCTAssertEqual(try metric3.currentValue()?.value, 3)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 0)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric3), 1)
    }

    func testSaveThroughMultipleHandles() throws {
        let (metric1, storage) = try metricAndStorage()
        let metric2 = try storage.metric(id: metric1.id, type: Int.self)
        XCTAssertEqual(storage.metrics().count, 1)

        XCTAssertNil(try metric1.currentValue())
        XCTAssertNil(try metric2.currentValue())

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 0)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 0)

        try metric1.update(1)

        XCTAssertEqual(try metric1.currentValue()?.value, 1)
        XCTAssertEqual(try metric2.currentValue()?.value, 1)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 1)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 1)

        try metric2.update(2)

        XCTAssertEqual(try metric1.currentValue()?.value, 2)
        XCTAssertEqual(try metric2.currentValue()?.value, 2)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 2)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 2)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try metric1.update(values)

        XCTAssertEqual(try metric1.currentValue()?.value, values.last!.value)
        XCTAssertEqual(try metric2.currentValue()?.value, values.last!.value)

        XCTAssertEqual(try storage.numberOfDataPoints(for: metric1), 2 + values.count)
        XCTAssertEqual(try storage.numberOfDataPoints(for: metric2), 2 + values.count)
    }
}
