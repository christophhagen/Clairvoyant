import XCTest
import Vapor
import Metrics
@testable import Clairvoyant
import ClairvoyantMetrics

final class MetricsTests: SelfCleaningTest {

    func testDoubleEncoding() {
        let value = 3.14
        let encoded = value.toData()
        guard let decoded = Double(fromData: encoded) else {
            XCTFail("Failed to decode double (\(encoded.count) bytes)")
            return
        }
        XCTAssertEqual(value, decoded)
    }

    func testBootstrap() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "observer.log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let metrics = MetricsProvider(observer: observer)
        MetricsSystem.bootstrap(metrics)

        let counter = Counter(label: "count")
        let result = 5
        counter.increment(by: result)

        guard let metric = observer.getMetric(id: counter.label, type: Int.self) else {
            XCTFail("No valid metric for counter")
            return
        }

        // Need to wait briefly here, since forwarding the log entry to the metric is done in an async context,
        // which would otherwise happen after trying to access the log data
        sleep(1)

        let last = await metric.lastValue()
        XCTAssertEqual(last?.value, result)

        let history = await metric.fullHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.value ?? 0, result)
    }

    func testEncodeTimestamped() throws {
        try encode(123)
        try encode(3.14)
        try encode("test")
    }

    private func encode<T>(_ value: T) throws where T: Codable, T: Equatable {
        let timestamped = Timestamped(value: value)
        let encoded = try JSONEncoder().encode(timestamped)
        let decoded: Timestamped<T> = try JSONDecoder().decode(from: encoded)
        XCTAssertEqual(timestamped.timestamp, decoded.timestamp)
        XCTAssertEqual(value, decoded.value)
    }

    func testDecodeAnyTimestamped() throws {
        let value = Timestamped(value: 123)
        let encoded = try JSONEncoder().encode(value)
        
        let decoded: AnyTimestamped = try JSONDecoder().decode(from: encoded)
        XCTAssertEqual(value.timestamp, decoded.timestamp)
    }
}
