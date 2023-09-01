import XCTest
import Vapor
import Metrics
@testable import Clairvoyant
import ClairvoyantMetrics
import ClairvoyantCBOR
import CBORCoding

final class MetricsTests: SelfCleaningTest {

    func testBootstrap() async throws {
        let observer = MetricObserver(logFileFolder: logFolder, logMetricId: "observer.log")
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

    func testDecodeAnyTimestamped() throws {
        let value = Timestamped(value: 123)
        let encoded = try CBOREncoder(dateEncodingStrategy: .secondsSince1970).encode(value)
        let decoded: AnyTimestamped = try CBORDecoder().decode(from: encoded)
        XCTAssertEqual(value.timestamp.timeIntervalSince1970, decoded.timestamp.timeIntervalSince1970)
    }
}
