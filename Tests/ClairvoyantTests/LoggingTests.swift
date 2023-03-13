import XCTest
import Logging
import Clairvoyant

final class LoggingTests: SelfCleaningTest {

    func testBootstrap() async throws {
        let observer = MetricObserver(logFolder: logFolder, logMetricId: "observer.log")
        LoggingSystem.bootstrap(observer.loggingBackend)

        let entry = "It works"
        let result = "[INFO] \(entry)"
        let logger = Logger(label: "log.something")
        logger.info(.init(stringLiteral: entry))

        guard let metric = observer.getMetric(id: logger.label, type: String.self) else {
            XCTFail("No valid metric for logger")
            return
        }

        // Need to wait briefly here, since forwarding the log entry to the metric is done in an async context,
        // which would otherwise happen after trying to access the log data
        sleep(1)

        let last = await metric.lastValue()
        XCTAssertEqual(last?.value, result)
        
        let history = await metric.fullHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.value ?? "", result)
    }
}
