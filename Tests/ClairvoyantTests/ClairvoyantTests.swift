import XCTest
@testable import Clairvoyant

final class ClairvoyantTests: XCTestCase {

    private var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    var logFolder: URL {
        temporaryDirectory.appendingPathComponent("logs")
    }

    override func setUp() async throws {
        try removeAllFiles()
    }

    override func tearDown() async throws {
        try removeAllFiles()
    }

    private func removeAllFiles() throws {
        let url = logFolder
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        MetricObserver.standard = nil
    }

    private func createObserver(logId: String = "log") -> MetricObserver {
        MetricObserver(
            logFolder: logFolder,
            logMetricId: logId,
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
    }

    func testCreateObserver() {
        _ = createObserver()
    }

    func testCreateMetricNoObserver() async throws {
        do {
            _ = try Metric<Int>("myInt")
        } catch MetricError.noObserver {

        }
    }

    func getIntMetricAndObserver() -> (metric: Metric<Int>, observer: MetricObserver) {
        let observer = createObserver()
        let metric: Metric<Int> = observer.addMetric(id: "myInt")
        return (metric, observer)
    }

    func testAddMetricToObserver() async throws {
        _ = getIntMetricAndObserver()
    }

    func testCreateMetricBootstrapped() async throws {
        let observer = createObserver()
        MetricObserver.standard = observer
        _ = try Metric<Int>("myInt")
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
        let observer = createObserver(logId: "test.log")
        MetricObserver.standard = observer
        let metric = try Metric<Int>("test.int")

        let start = Date()
        let input = [0,1,2]
        for i in input {
            try await metric.update(i)
        }

        let end = Date()
        let data = await metric.encodedHistoryData(from: start, to: end)
        let decoder = JSONDecoder()

        let values: [Int] = try decoder.decode([Timestamped<Int>].self, from: data).map { $0.value }
        XCTAssertEqual(values, input)
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

    func testNoLocalLogging() async throws {
        let observer = createObserver()
        let metric: Metric<Int> = observer.addMetric(id: "myInt", keepsLocalHistoryData: false)

        let result1 = try await metric.update(1)
        XCTAssertTrue(result1)

        let result2 = try await metric.update(2)
        XCTAssertTrue(result2)

        let history = await metric.fullHistory()
        XCTAssertTrue(history.isEmpty)

        let last = await metric.lastValue()
        XCTAssertEqual(last?.value, 2)
    }

    func testDeleteHistory() async throws {
        let observer = createObserver()
        let metric: Metric<Int> = observer.addMetric(id: "myInt")

        let startDate = Date()
        let deleteDate = startDate.addingTimeInterval(1)
        let endDate = startDate.addingTimeInterval(2)

        let result1 = try await metric.update(1, timestamp: startDate)
        XCTAssertTrue(result1)
        let result2 = try await metric.update(2, timestamp: endDate)
        XCTAssertTrue(result2)

        let history1 = await metric.fullHistory()
        XCTAssertEqual(history1.count, 2)

        try await metric.deleteHistory(before: deleteDate)
        let history2 = await metric.fullHistory()
        XCTAssertEqual(history2.count, 1)
        XCTAssertEqual(history2.first?.value, 2)

        let last = await metric.lastValue()
        XCTAssertEqual(last?.value, 2)
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
