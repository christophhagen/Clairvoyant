import XCTest
import Clairvoyant
import CBORCoding

final class MyAuthenticator: MetricAccessAuthenticator {
    
    func metricListAccess(isAllowedForToken accessToken: Data) -> Bool {
        true
    }

    func metricAccess(to metric: Clairvoyant.MetricId, isAllowedForToken accessToken: Data) -> Bool {
        true
    }
}

final class ClairvoyantTests: XCTestCase {

    private var temporaryDirectory: URL {
        if #available(macOS 13.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    private var logFolder: URL {
        temporaryDirectory.appendingPathComponent("logs")
    }

    override func tearDown() async throws {
        let url = logFolder
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func testUpdatingMetric() async throws {
        let authenticator = MyAuthenticator()

        let metric = Metric<Int>("myInt")

        let observer = MetricObserver(logFolder: logFolder, authenticator: authenticator, logMetricId: "log")
        observer.observe(metric)

        let start = Date()


        XCTAssertTrue(metric.update(1))

        do {
            guard let lastValue = metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 1)
        }

        XCTAssertTrue(metric.update(2))

        do {
            guard let lastValue = metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 2)
        }

        XCTAssertTrue(metric.update(3))

        do {
            guard let lastValue = metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 3)
        }

        let range = start...Date()
        let history: [Timestamped<Int>] = try metric.getHistory(in: range)
        XCTAssertEqual(history.map { $0.value }, [1, 2, 3])
    }
}
