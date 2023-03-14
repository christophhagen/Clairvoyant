import XCTest
import Vapor
@testable import Clairvoyant
import CBORCoding

final class ClairvoyantTests: SelfCleaningTest {

    func testCreateObserver() {
        _ = MetricObserver(logFolder: logFolder, logMetricId: "log")
    }

    func testCreateMetricNoObserver() async throws {
        do {
            _ = try await Metric<Int>("myInt")
        } catch MetricError.noObserver {

        }
    }

    func getIntMetricAndObserver() -> (metric: Metric<Int>, observer: MetricObserver) {
        let observer = MetricObserver(logFolder: logFolder, logMetricId: "log")
        let metric: Metric<Int> = observer.addMetric(id: "myInt")
        return (metric, observer)
    }

    func testAddMetricToObserver() async throws {
        _ = getIntMetricAndObserver()
    }

    func testCreateMetricBootstrapped() async throws {
        let observer = MetricObserver(logFolder: logFolder, logMetricId: "log")
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
        let observer = MetricObserver(logFolder: logFolder, logMetricId: "test.log")
        MetricObserver.standard = observer
        let metric = try await Metric<Int>("test.int")

        let start = Date()
        let input = [0,1,2]
        for i in input {
            try await metric.update(i)
        }

        let end = Date()
        let data = await metric.history(from: start, to: end)

        let client = MetricConsumer(url: URL(fileURLWithPath: ""), accessProvider: MetricAccessToken(accessToken: Data()))
        let values: [Int] = try await client.decode(logData: data).map { $0.value }
        XCTAssertEqual(values, input)

        let generic = await client.metric(from: metric.description)
        let genericValues = try await generic.decode(data, type: Int.self).map { $0.description }
        XCTAssertEqual(genericValues, input.map { "\($0)"})
    }

    func testMultipleLogFiles() async throws {
        let observer = getIntMetricAndObserver()
        let metric = observer.metric

        // 10 MByte per file
        // Around 12 B per entry
        for i in 0..<1_000_000 {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(i))
            try await metric.update(i, timestamp: timestamp)
            if i % 100000 == 0 { print("\(i) updates completed") }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFolder.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: logFolder.path).count, 1)

        let url = logFolder.appendingPathComponent(metric.idHash)
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3) // Last value + 2 log files
        let sizes = try files.map {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            let size = Int(attributes[.size] as? UInt64 ?? 0)
            print("\($0.lastPathComponent): \(size) bytes")
            return size
        }
        let totalSize = sizes.reduce(0, +)
        let averageSize = Double(totalSize)/1_000_000
        let largerFileSize = sizes.max()!
        XCTAssertTrue(totalSize > LogFileWriter.maximumFileSizeInBytes)
        print("Total \(totalSize) bytes, average \(averageSize) bytes, max \(largerFileSize)")

        print("Checking first file")
        // Get entries from first file
        let h1 = await metric.history(in: Date(0)...Date(100))
        XCTAssertEqual(h1.count, 101)

        print("Checking both files")
        // Get entries from both files
        let start = Double(largerFileSize)/averageSize - 5000
        let h2 = await metric.history(in: Date(start)...Date(start + 10000))
        XCTAssertEqual(h2.count, 10000)

        print("Checking last file")
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
