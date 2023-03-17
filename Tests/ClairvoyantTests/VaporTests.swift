import XCTest
import XCTVapor
import Vapor
import ClairvoyantVapor
import ClairvoyantCBOR
@testable import Clairvoyant
import CBORCoding

final class VaporTests: SelfCleaningTest {

    func testMetricList() async throws {
        let observer = MetricObserver(
            logFileFolder: logFolder,
            logMetricId: "log")
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())

        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = CBORDecoder()

        try app.test(.POST, "metrics/list", headers: ["token" : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: [MetricDescription] = try decoder.decode(from: body)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.id, "log")
            XCTAssertEqual(result.first?.dataType, .string)
        })
    }

    func testAllLastValues() async throws {
        let observer = MetricObserver(
            logFileFolder: logFolder,
            logMetricId: "log")
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = CBORDecoder()

        try app.test(.POST, "metrics/last/all", headers: ["token" : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: [String : Data] = try decoder.decode(from: body)
            XCTAssertEqual(result.count, 1)
            guard let data = result["log".hashed()] else {
                XCTFail()
                return
            }
            let decoded: Timestamped<String> = try decoder.decode(from: data)
            XCTAssertEqual(decoded.value, "test")
        })
    }

    func testLastValue() async throws {
        let observer = MetricObserver(
            logFileFolder: logFolder,
            logMetricId: "log")
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = CBORDecoder()
        let hash = "log".hashed()

        try app.test(.POST, "metrics/last/\(hash)", headers: ["token" : ""], afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result: Timestamped<String> = try decoder.decode(from: body)
            XCTAssertEqual(result.value, "test")
        })
    }

    func testHistory() async throws {
        let observer = MetricObserver(
            logFileFolder: logFolder,
            logMetricId: "log")
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = CBORDecoder()
        let hash = "log".hashed()
        let request = MetricHistoryRequest(start: .distantPast, end: .distantFuture)
        let body = try CBOREncoder(dateEncodingStrategy: .secondsSince1970).encode(request)

        try app.test(.POST, "metrics/history/\(hash)",
                     headers: ["token" : ""],
                     body: .init(data: body),
                     afterResponse: { res in

            XCTAssertEqual(res.status, .ok)
            let body = Data(res.body.readableBytesView)
            let result = try decoder.decode([Timestamped<String>].self, from: body)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.value, "test")
        })
    }
}
