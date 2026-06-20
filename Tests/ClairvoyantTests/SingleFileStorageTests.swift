import XCTest
import Clairvoyant
import MetricFileStorage

final class SingleFileStorageTests: XCTestCase {

    override func setUpWithError() throws {
        self.continueAfterFailure = false

        try removeAllFiles()
    }

    override func tearDownWithError() throws {
        try removeAllFiles()
    }

    private func removeAllFiles() throws {
        do {
            try logFolder.removeIfPresent()
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

    private var logFolder: URL {
        temporaryDirectory.appendingPathComponent("db", isDirectory: true)
    }

    private func database() async throws -> SingleFileStorage {
        try await SingleFileStorage(
            logFolder: logFolder,
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
    }

    func testCreateDatabase() async throws {
        _ = try await database()
    }

    private func metricAndStorage() async throws -> (metric: AsyncMetric<Int>, storage: SingleFileStorage) {
        let storage = try await database()
        let metric: AsyncMetric<Int> = try await storage.metric(id: "metric", group: "test")
        return (metric, storage)
    }

    func testCreateMetric() async throws {
        let (metric, storage) = try await metricAndStorage()
        let metrics = await storage.metrics()
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics[0], metric.info)
    }

    func testDeleteMetric() async throws {
        let (metric, storage) = try await metricAndStorage()

        try await storage.delete(metric)

        let metrics = await storage.metrics()
        XCTAssertEqual(metrics.count, 0)
    }

    func testStoreValue() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value = 123
        try await metric.update(value)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
    }

    func testStoreValueWithTimestamp() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value = 123
        let timestamp = Date.now
        let updated = try await metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testStoreMultipleValues() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value1 = 123
        let timestamp1 = Date.now
        let updated1 = try await metric.update(value1, timestamp: timestamp1)
        XCTAssertTrue(updated1)

        let current1 = try await metric.currentValue()
        XCTAssertNotNil(current1)
        XCTAssertEqual(current1!.value, value1)
        XCTAssertEqual(current1!.timestamp, timestamp1)

        let value2 = 234
        let timestamp2 = timestamp1.addingTimeInterval(1)
        let updated2 = try await metric.update(value2, timestamp: timestamp2)
        XCTAssertTrue(updated2)

        let current2 = try await metric.currentValue()
        XCTAssertNotNil(current2)
        XCTAssertEqual(current2!.value, value2)
        XCTAssertEqual(current2!.timestamp, timestamp2)

        let value3 = 345
        let timestamp3 = timestamp2.addingTimeInterval(1)
        let updated3 = try await metric.update(value3, timestamp: timestamp3)
        XCTAssertTrue(updated3)

        let current3 = try await metric.currentValue()
        XCTAssertNotNil(current3)
        XCTAssertEqual(current3!.value, value3)
        XCTAssertEqual(current3!.timestamp, timestamp3)
    }

    func testStoreSameValue() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value = 123
        let timestamp = Date.now
        let updated = try await metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        // Update again with newer timestamp
        let updatedAgain = try await metric.update(value, timestamp: timestamp.addingTimeInterval(1))
        XCTAssertFalse(updatedAgain)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testStoreOldValue() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value = 123
        let timestamp = Date.now
        let updated = try await metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)

        // Update again with older timestamp
        let updatedAgain = try await metric.update(234, timestamp: timestamp.addingTimeInterval(-1))
        XCTAssertFalse(updatedAgain)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, value)
        XCTAssertEqual(current!.timestamp, timestamp)
    }

    func testComplexValue() async throws {
        struct Value: Codable, MetricValue {
            static var valueType: MetricType = "Value"
            let id: Int
            let name: String
        }
        let storage = try await database()
        let metric: AsyncMetric<Value> = try await storage.metric(id: "metric", group: "test")

        let value = Value(id: 123, name: "123")
        let timestamp = Date.now
        let updated = try await metric.update(value, timestamp: timestamp)
        XCTAssertTrue(updated)
    }

    func testStoreBatch() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values: [Timestamped<Int>] = [
            .init(value: 123, timestamp: date),
            .init(value: 234, timestamp: date.addingTimeInterval(1)),
            .init(value: 345, timestamp: date.addingTimeInterval(2))
        ]
        try await metric.update(values)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values.last!.value)
        XCTAssertEqual(current!.timestamp, values.last!.timestamp)
    }

    func testStoreOutOfOrderBatch() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values: [Timestamped<Int>] = [
            .init(value: 345, timestamp: date.addingTimeInterval(2)),
            .init(value: 123, timestamp: date),
            .init(value: 234, timestamp: date.addingTimeInterval(1)),
        ]
        try await metric.update(values)

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values.first!.value)
        XCTAssertEqual(current!.timestamp, values.first!.timestamp)
    }

    func testStorePartiallyOutdatedBatch() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let value = 345
        let date = Date.now

        let updated = try await metric.update(value, timestamp: date.addingTimeInterval(1))
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
        try await metric.update(values)

        let history = try await metric.history()
        for item in history {
            print("\(item.timestamp.timeIntervalSinceReferenceDate): \(item.value)")
        }

        let current = try await metric.currentValue()
        XCTAssertNotNil(current)
        XCTAssertEqual(current!.value, values[6].value)
        XCTAssertEqual(current!.timestamp, values[6].timestamp)
    }

    func testFullHistory() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric.update(values)

        let stored = try await metric.history()
        XCTAssertEqual(stored, values)
    }

    func testReverseHistory() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric.update(values)

        let stored = try await metric.history(from: .distantFuture, to: .distantPast)
        XCTAssertEqual(stored, values.reversed())
    }

    func testPartialHistory() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric.update(values)

        let stored = try await metric.history(
            from: date.addingTimeInterval(15.5),
            to: date.addingTimeInterval(35.5))
        XCTAssertEqual(stored, Array(values[15...34]))
    }

    func testDeleteAllValues() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric.update(values)

        try await metric.deleteHistory()

        let stored = try await metric.history()
        let current = try await metric.currentValue()
        XCTAssertEqual(stored.count, 0)
        XCTAssertNil(current)
    }

    func testDeleteSomeValues() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        let end = date.addingTimeInterval(35.5)
        try await metric.update(values)

        try await metric.deleteHistory(before: end)

        let deleted = try await metric.history(to: end)
        XCTAssertEqual(deleted.count, 0)

        let remaining = try await metric.history()
        XCTAssertEqual(remaining, Array(values[35...]))
    }

    func testDeletesMetricDataAfterMetricDeletion() async throws {
        let (metric, storage) = try await metricAndStorage()
        let count = await storage.metrics().count // To keep `storage` from being deallocated
        XCTAssertEqual(count, 1)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric.update(values)

        let pointsBeforeDelete = try await storage.numberOfDataPoints(for: metric.id)
        XCTAssertEqual(pointsBeforeDelete, values.count)

        try await storage.delete(metric)
        await XCTAssertEqualAsync(await storage.metrics().count, 0)

        let pointsAfterDelete = try await storage.numberOfDataPoints(for: metric.id)
        XCTAssertEqual(pointsAfterDelete, 0)
    }

    func testCreateMultipleMetrics() async throws {
        let (_, storage) = try await metricAndStorage()
        await XCTAssertEqualAsync(await storage.metrics().count, 1)

        let id = MetricId(id: "m2", group: "test")
        let name = "Metric 2"
        let description = "Metric 2 Description"
        let metric2 = try await storage.metric(id: id, name: name, description: description, type: String.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 2)
        XCTAssertEqual(metric2.id, id)
        XCTAssertEqual(metric2.name, name)
        XCTAssertEqual(metric2.description, description)

        // Create new handle to check that info is correctly loaded
        let metric3 = try await storage.metric(id: id, type: String.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 2)
        XCTAssertEqual(metric3.id, id)
        XCTAssertEqual(metric3.name, name)
        XCTAssertEqual(metric3.description, description)
    }

    func testUpdateMetricInfo() async throws {
        let (metric, storage) = try await metricAndStorage()
        await XCTAssertEqualAsync(await storage.metrics().count, 1)

        let name = "Metric 2"
        let description = "Metric 2 Description"
        let metric2 = try await storage.metric(id: metric.id, name: name, description: description, type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 1)
        XCTAssertEqual(metric2.id, metric.id)
        XCTAssertEqual(metric2.name, name)
        XCTAssertEqual(metric2.description, description)

        // Old handle still has old information
        XCTAssertNotEqual(metric.name, name)
        XCTAssertNotEqual(metric.description, description)

        // Create new handle to check that info is correctly loaded
        let metric3 = try await storage.metric(id: metric.id, type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 1)
        XCTAssertEqual(metric3.id, metric.id)
        XCTAssertEqual(metric3.name, name)
        XCTAssertEqual(metric3.description, description)
    }

    func testHandleWithInvalidType() async throws {
        let (metric, storage) = try await metricAndStorage()
        await XCTAssertEqualAsync(await storage.metrics().count, 1)

        do {
            _ = try await storage.metric(id: metric.id, type: String.self)
        } catch let error as FileStorageError where error.operation == .metricType {

        } catch {
            XCTFail("Should not be able to create metric with same ids and different types")
        }
    }

    func testStoreDataInMultipleMetrics() async throws {
        let (metric, storage) = try await metricAndStorage()
        let metric2 = try await storage.metric(id: "2", group: "test", type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 2)

        try await metric.update(1)
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric.id), 1)
        await XCTAssertNilAsync(try await metric2.currentValue())
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 0)

        try await metric2.update(2)
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric.id), 1)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 2)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 1)

        try await metric.update(3)
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, 3)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric.id), 2)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 2)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 1)

        try await metric2.update(4)
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, 3)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric.id), 2)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 4)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 2)
    }

    func testDeleteOneOfMultipleMetrics() async throws {
        let (metric1, storage) = try await metricAndStorage()
        let metric2 = try await storage.metric(id: "2", group: "test", type: Int.self)
        let metric3 = try await storage.metric(id: "3", group: "test", type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 3)

        try await metric1.update(1)
        try await metric2.update(2)
        try await metric3.update(3)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 2)
        await XCTAssertEqualAsync(try await metric3.currentValue()?.value, 3)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric3.id), 1)

        try await storage.delete(metric2)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await metric3.currentValue()?.value, 3)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric3.id), 1)

        func catchError(_ msg: String, _ block: () async throws -> Void) async {
            do {
                try await block()
            } catch let error as FileStorageError where error.operation == .metricId {

            } catch {
                XCTFail("Should not be able to \(msg)")
            }
        }
        await catchError("get current value of deleted metric") {
            _ = try await metric2.currentValue()
        }

        await catchError("update value of deleted metric") {
            _ = try await metric2.update(1)
        }

        await catchError("get history of deleted metric") {
            _ = try await metric2.history()
        }

        await catchError("delete already deleted metric") {
            try await storage.delete(metric2)
        }
    }

    func testDeleteHistoryOfOneMetric() async throws {
        let (metric1, storage) = try await metricAndStorage()
        let metric2 = try await storage.metric(id: "2", group: "test", type: Int.self)
        let metric3 = try await storage.metric(id: "3", group: "test", type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 3)

        try await metric1.update(1)
        try await metric2.update(2)
        try await metric3.update(3)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 2)
        await XCTAssertEqualAsync(try await metric3.currentValue()?.value, 3)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric3.id), 1)

        try await metric2.deleteHistory()

        await XCTAssertNilAsync(try await metric2.currentValue())

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await metric3.currentValue()?.value, 3)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 0)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric3.id), 1)
    }

    func testSaveThroughMultipleHandles() async throws {
        let (metric1, storage) = try await metricAndStorage()
        let metric2 = try await storage.metric(id: metric1.id, type: Int.self)
        await XCTAssertEqualAsync(await storage.metrics().count, 1)

        await XCTAssertNilAsync(try await metric1.currentValue())
        await XCTAssertNilAsync(try await metric2.currentValue())

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 0)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 0)

        try await metric1.update(1)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 1)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 1)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 1)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 1)

        try await metric2.update(2)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, 2)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, 2)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 2)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 2)

        let date = Date.now
        let values = (1...100).map { $0.timestamped(with: date.addingTimeInterval(Double($0))) }

        try await metric1.update(values)

        await XCTAssertEqualAsync(try await metric1.currentValue()?.value, values.last!.value)
        await XCTAssertEqualAsync(try await metric2.currentValue()?.value, values.last!.value)

        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric1.id), 2 + values.count)
        await XCTAssertEqualAsync(try await storage.numberOfDataPoints(for: metric2.id), 2 + values.count)
    }

    func testStringMetric() async throws {
        let storage = try await database()
        let metric = try await storage.metric(id: "some", group: "test", type: String.self)

        try await metric.update("First")
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, "First")

        try await metric.update("Second")
        await XCTAssertEqualAsync(try await metric.currentValue()?.value, "Second")
    }
}

func XCTAssertEqualAsync<T>(
    _ expression1: @autoclosure () async throws -> T,
    _ expression2: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async where T : Equatable {
    do {
        let value1 = try await expression1()
        let value2 = try await expression2()
        XCTAssertEqual(value1, value2, file: file, line: line)
    } catch {
        XCTFail(error.localizedDescription, file: file, line: line)
    }
}

func XCTAssertNilAsync(
    _ expression: @autoclosure () async throws -> Any?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        let value = try await expression()
        XCTAssertNil(value, file: file, line: line)
    } catch {
        XCTFail(error.localizedDescription, file: file, line: line)
    }
}
