import XCTest
import Vapor
@testable import Clairvoyant
import ClairvoyantCBOR
import CBORCoding

final class ClairvoyantTests: SelfCleaningTest {

    func testCreateObserver() {
        _ = MetricObserver(logFileFolder: logFolder, logMetricId: "log")
    }

    func testCreateMetricNoObserver() async throws {
        do {
            _ = try await Metric<Int>("myInt")
        } catch MetricError.noObserver {

        }
    }

    func getIntMetricAndObserver() -> (metric: Metric<Int>, observer: MetricObserver) {
        let observer = MetricObserver(logFileFolder: logFolder, logMetricId: "log")
        let metric: Metric<Int> = observer.addMetric(id: "myInt")
        return (metric, observer)
    }

    func testAddMetricToObserver() async throws {
        _ = getIntMetricAndObserver()
    }

    func testCreateMetricBootstrapped() async throws {
        let observer = MetricObserver(logFileFolder: logFolder, logMetricId: "log")
        MetricObserver.standard = observer
        _ = try await Metric<Int>("myInt")
    }

    func testUpdatingMetric() async throws {
        let observer = getIntMetricAndObserver()
        let metric = observer.metric

        let start = Date()

        let stored = try await metric.update(1)
        XCTAssertTrue(stored)

        do {
            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 1)
        }

        do {
            let stored = try await metric.update(2)
            XCTAssertTrue(stored)

            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 2)
        }

        do {
            let stored = try await metric.update(3)
            XCTAssertTrue(stored)

            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 3)
        }

        let range = start.addingTimeInterval(-1)...Date()
        let history: [Timestamped<Int>] = await metric.history(in: range)
        XCTAssertEqual(history.map { $0.value }, [1, 2, 3])
    }

    func testClientHistoryDecoding() async throws {
        let observer = MetricObserver(logFileFolder: logFolder, logMetricId: "test.log")
        MetricObserver.standard = observer
        let metric = try await Metric<Int>("test.int")

        let start = Date()
        let input = [0,1,2]
        for i in input {
            try await metric.update(i)
        }

        let end = Date()
        let data = await metric.encodedHistoryData(from: start, to: end)
        let decoder = CBORDecoder()

        let client = MetricConsumer(from: URL(fileURLWithPath: ""), accessProvider: MetricAccessToken(accessToken: Data()))
        let values: [Int] = try decoder.decode([Timestamped<Int>].self, from: data).map { $0.value }
        XCTAssertEqual(values, input)

        let generic = await client.metric(from: metric.description)
        let genericValues = try await generic.decodeTimestampedArray(data, type: Int.self).map { $0.description }
        XCTAssertEqual(genericValues, input.map { "\($0)"})
    }

    func testMultipleLogFiles() async throws {
        let observer = getIntMetricAndObserver()
        let metric = observer.metric

        // 1 MByte per file
        await metric.setMaximumFileSize(1_000_000)

        // Around 15 B per entry
        let values = (0..<100_000).map { Timestamped<Int>(value: $0, timestamp: Date(timeIntervalSince1970: TimeInterval($0))) }
        try await metric.update(values)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFolder.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: logFolder.path).count, 1)

        let url = logFolder.appendingPathComponent(metric.idHash)
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3) // Last value + 2 log files
        let sizes = try files.map {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            let size = Int(attributes[.size] as? UInt64 ?? 0)
            print("File '\($0.lastPathComponent)': \(size) bytes")
            return size
        }
        let totalSize = sizes.reduce(0, +)
        let averageSize = Double(totalSize)/100_000
        let largerFileSize = sizes.max()!
        XCTAssertTrue(totalSize > 1_000_000)
        print("Total \(totalSize) bytes, average \(averageSize) bytes, max \(largerFileSize)")

        // Get entries from first file
        let h1 = await metric.history(in: Date(0)...Date(100))
        XCTAssertEqual(h1.count, 101)

        // Get entries from both files
        let start = Double(largerFileSize)/averageSize - 5000
        let h2 = await metric.history(in: Date(start)...Date(start + 10000))
        XCTAssertEqual(h2.count, 10000)

        // Get entries from last file
        let h3 = await metric.history(in: Date(start + 10000)...Date(start + 20000))
        XCTAssertEqual(h3.count, 10000)
    }

    func testLastValue() async throws {
        let value = 123
        do {
            let observer = getIntMetricAndObserver()
            try await observer.metric.update(value)
        }
        do {
            let observer = getIntMetricAndObserver()
            let last = await observer.metric.lastValue()
            XCTAssertNotNil(last)
            if let last {
                XCTAssertEqual(last.value, value)
            }
        }
    }

    func testOldValue() async throws {
        let observer = getIntMetricAndObserver()
        let result1 = try await observer.metric.update(1)
        XCTAssertTrue(result1)

        let result2 = try await observer.metric.update(2, timestamp: Date().advanced(by: -1))
        XCTAssertFalse(result2)
    }

}

private extension Date {

    init(_ time: Int) {
        self.init(timeIntervalSince1970: TimeInterval(time))
    }

    init(_ time: TimeInterval) {
        self.init(timeIntervalSince1970: time)
    }

    static func at(_ time: Int) -> Date {
        at(TimeInterval(time))
    }

    static func at(_ time: TimeInterval) -> Date {
        .init(timeIntervalSince1970: time)
    }
}
