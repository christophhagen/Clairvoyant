import XCTest
import Clairvoyant
import MetricFileStorage

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
    }

    private func createStorage(logId: String = "log", logGroup: String = "test", fileSize: Int = 10_000_000) async throws -> FileBasedMetricStorage {
        try await .init(
            logFolder: logFolder,
            logMetricId: logId, 
            logMetricGroup: logGroup,
            encoderCreator: JSONEncoder.init,
            decoderCreator: JSONDecoder.init,
            fileSize: fileSize)
    }

    func testCreateStorage() async throws {
        _ = try await createStorage()
    }

    func getIntMetricAndStorage(fileSize: Int = 10_000_000) async throws -> (metric: AsyncMetric<Int>, storage: FileBasedMetricStorage) {
        let storage = try await createStorage(fileSize: fileSize)
        let metric: AsyncMetric<Int> = try await storage.metric("int", group: "test")
        return (metric, storage)
    }

    func testAddMetricToObserver() async throws {
        _ = try await getIntMetricAndStorage()
    }
    
    func testUpdatingMetric() async throws {
        let data = try await getIntMetricAndStorage()
        let metric = data.metric

        let start = Date()

        let stored = try await metric.update(1)
        XCTAssertTrue(stored)

        do {
            guard let lastValue = try await metric.currentValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 1)
        }

        do {
            let stored = try await metric.update(2)
            XCTAssertTrue(stored)

            guard let lastValue = try await metric.currentValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 2)
        }

        do {
            let stored = try await metric.update(3)
            XCTAssertTrue(stored)

            guard let lastValue = try await metric.currentValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 3)
        }

        let range = start.addingTimeInterval(-1)...Date()
        let history: [Timestamped<Int>] = try await metric.history(in: range)
        XCTAssertEqual(history.map { $0.value }, [1, 2, 3])
    }

    func testMultipleLogFiles() async throws {
        let fileSize = 100_000
        let valueCount = fileSize / 10
        // 100 KByte per file
        let data = try await getIntMetricAndStorage(fileSize: fileSize)
        let metric = data.metric

        // Around 15 B per entry
        let values = (0..<valueCount).map {
            Timestamped<Int>(value: $0, timestamp: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        try await metric.update(values)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFolder.path))
        //XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: logFolder.path).count, 1)

        let url = logFolder.appendingPathComponent("test/int")
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3) // Last value + 2 log files
        let sizes = try files.map {
            let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
            let size = Int(attributes[.size] as? UInt64 ?? 0)
            print("File '\($0.lastPathComponent)': \(size) bytes")
            return size
        }
        let totalSize = sizes.reduce(0, +)
        let averageSize = Double(totalSize)/Double(valueCount)
        let largerFileSize = sizes.max()!
        XCTAssertTrue(totalSize > fileSize)
        print("Total \(totalSize) bytes, average \(averageSize) bytes, max \(largerFileSize)")

        // Get entries from first file
        let h1 = try await metric.history(in: Date(0)...Date(100))
        XCTAssertEqual(h1.count, 101)

        // Get entries from both files
        let start = Double(largerFileSize)/averageSize - 5000
        let batchSize = valueCount / 10
        let batch = Double(batchSize)
        let h2 = try await metric.history(in: Date(start)...Date(start + batch))
        XCTAssertEqual(h2.count, batchSize)

        // Get entries from last file
        let h3 = try await metric.history(in: Date(start+batch)...Date(start+2*batch))
        XCTAssertEqual(h3.count, batchSize)
    }

    func testLastValue() async throws {
        let value = 123
        do {
            let data = try await getIntMetricAndStorage()
            try await data.metric.update(value)
        }
        do {
            let data = try await getIntMetricAndStorage()
            let last = try await data.metric.currentValue()
            XCTAssertNotNil(last)
            if let last {
                XCTAssertEqual(last.value, value)
            }
        }
    }

    func testOldValue() async throws {
        let data = try await getIntMetricAndStorage()
        let result1 = try await data.metric.update(1)
        XCTAssertTrue(result1)

        let result2 = try await data.metric.update(2, timestamp: Date().advanced(by: -1))
        XCTAssertFalse(result2)
    }

    func testDeleteHistory() async throws {
        let storage = try await createStorage()
        let metric: AsyncMetric<Int> = try await storage.metric("myInt", group: "test")

        let startDate = Date()
        let deleteDate = startDate.addingTimeInterval(1)
        let endDate = startDate.addingTimeInterval(2)

        let result1 = try await metric.update(1, timestamp: startDate)
        XCTAssertTrue(result1)
        
        let result2 = try await metric.update(2, timestamp: endDate)
        XCTAssertTrue(result2)

        let history1 = try await metric.history()
        XCTAssertEqual(history1.count, 2)

        try await metric.deleteHistory(to: deleteDate)
        let history2 = try await metric.history()
        XCTAssertEqual(history2.count, 1)
        XCTAssertEqual(history2.first?.value, 2)

        let last = try await metric.currentValue()
        XCTAssertEqual(last?.value, 2)
    }
    
    func testReverseHistoryBatch() async throws {
        let storage = try await createStorage()
        let metric: AsyncMetric<Int> = try await storage.metric("myInt", group: "test")
        let now = Date.now
        let values = (1...100).reversed().map { Timestamped(value: $0, timestamp: now.advanced(by: TimeInterval(-$0))) }
        try await metric.update(values)
        
        let newestBatch = try await metric.history(from: now, to: .distantPast, limit: 100)
        XCTAssertEqual(newestBatch, values.suffix(100).reversed())
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
