import XCTest
@testable import Clairvoyant
import CBORCoding

final class MyAuthenticator: MetricAccessManager {
    
    func metricListAccess(isAllowedForToken accessToken: Data) throws {

    }

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: Data) throws {

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

        let observer = MetricObserver(logFolder: logFolder, accessManager: authenticator, logMetricId: "log")
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

    func testClientHistoryDecoding() async throws {
        let observer = MetricObserver(logFolder: logFolder, accessManager: MyAuthenticator(), logMetricId: "test.log")
        let metric = Metric<Int>("test.int")
        XCTAssertTrue(observer.observe(metric))

        let start = Date()
        let input = [0,1,2]
        input.forEach {
            XCTAssertTrue(metric.update($0))
        }

        let end = Date()
        let range = start...end


        let data = try observer.getHistoryFromLog(forMetric: metric, in: range)

        let client = MetricConsumer(url: URL(fileURLWithPath: ""), accessProvider: MetricAccessToken(accessToken: Data()))
        let values: [Int] = try client.decode(logData: data).map { $0.value }
        XCTAssertEqual(values, input)

        let generic = client.metric(from: metric.description)
        let genericValues = try generic.decode(data, type: Int.self).map { $0.description }
        XCTAssertEqual(genericValues, input.map { "\($0)"})
    }
}
