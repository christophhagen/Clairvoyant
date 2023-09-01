import XCTest
import XCTVapor
import Vapor
import ClairvoyantVapor
@testable import Clairvoyant

final class VaporTests: SelfCleaningTest {

    func testMetricList() async throws {
        let observer = MetricObserver(
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())

        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()

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
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()

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
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()
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
            logFolder: logFolder,
            logMetricId: "log",
            encoder: JSONEncoder(),
            decoder: JSONDecoder())
        let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
        observer.log("test")
        let app = Application(.testing)
        defer { app.shutdown() }
        provider.registerRoutes(app)

        let decoder = JSONDecoder()
        let hash = "log".hashed()
        let request = MetricHistoryRequest(start: .distantPast, end: .distantFuture)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let body = try encoder.encode(request)

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
