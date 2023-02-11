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

        let metric = await Metric<Int>("myInt")

        let observer = await MetricObserver(logFolder: logFolder, accessManager: authenticator, logMetricId: "log")
        await observer.observe(metric)

        let start = Date()

        do {
            let result = await metric.update(1)
            XCTAssertTrue(result)
        }

        do {
            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 1)
        }

        do {
            let result = await metric.update(2)
            XCTAssertTrue(result)
        }

        do {
            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 2)
        }

        do {
            let result = await metric.update(3)
            XCTAssertTrue(result)
        }

        do {
            guard let lastValue = await metric.lastValue() else {
                XCTFail("No last value despite saving one")
                return
            }
            XCTAssertEqual(lastValue.value, 3)
        }

        let range = start...Date()
        let history: [Timestamped<Int>] = try await metric.getHistory(in: range)
        XCTAssertEqual(history.map { $0.value }, [1, 2, 3])
    }

    func testClientHistoryDecoding() async throws {
        let observer = await MetricObserver(logFolder: logFolder, accessManager: MyAuthenticator(), logMetricId: "test.log")
        let metric = await Metric<Int>("test.int")
        do {
            let result = await observer.observe(metric)
            XCTAssertTrue(result)
        }

        let start = Date()
        let input = [0,1,2]
        for i in input {
            let result = await metric.update(i)
            XCTAssertTrue(result)
        }

        let end = Date()
        let range = start...end


        let data = try await observer.getHistoryFromLog(forMetric: metric, in: range)

        let client = MetricConsumer(url: URL(fileURLWithPath: ""), accessProvider: MetricAccessToken(accessToken: Data()))
        let values: [Int] = try await client.decode(logData: data).map { $0.value }
        XCTAssertEqual(values, input)

        let generic = await client.metric(from: metric.description)
        let genericValues = try await generic.decode(data, type: Int.self).map { $0.description }
        XCTAssertEqual(genericValues, input.map { "\($0)"})
    }
}
