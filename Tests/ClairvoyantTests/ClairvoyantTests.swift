import XCTest
@testable import Clairvoyant
import CBORCoding

final class MyEmitter: ServerOwner {

    var value: Timestamped<Int>

    init() {
        self.value = .init(value: 0)
    }

    var authenticationMethod: Clairvoyant.PropertyAuthenticationMethod {
        .accessToken
    }

    func hasListAccessPermission(_ accessData: Data) -> Bool {
        true
    }

    func hasReadPermission(for property: UInt32, accessData: Data) -> Bool {
        true
    }

    func hasWritePermission(for property: UInt32, accessData: Data) -> Bool {
        true
    }

    func getPropertyList(for accessData: Data) -> [Clairvoyant.PropertyDescription] {
        []
    }

    func getHistoryOfProperty(withId uniqueId: UInt32, in range: ClosedRange<Date>) async throws -> Data {
        .init()
    }

    func registerAll(with manager: PropertyManager) {
        let property = PropertyRegistration(
            uniqueId: 123,
            name: "Prop",
            updates: .interval(5, updateProp),
            isLogged: true,
            allowsManualUpdate: true,
            read: readProp,
            write: writeProp)
        manager.register(property, for: self)
    }

    func updateProp() async throws -> Timestamped<Int> {
        value = .init(value: value.value + 1)
        return value
    }

    func readProp() async throws -> Timestamped<Int> {
        value
    }

    func writeProp(_ value: Int) async throws {
        self.value = .init(value: value)
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

    func test() async throws {
        let emitter = MyEmitter()

        let manager = PropertyManager(
            logFolder: logFolder,
            serverOwner: emitter)
        emitter.registerAll(with: manager)

        let start = Date()

        let propertyId = PropertyId(owner: emitter.name, uniqueId: 123)

        try manager.deleteLogfile(for: propertyId)

        do {
            let initial: Timestamped<Int> = try await manager.getValue(for: propertyId)
            XCTAssertEqual(initial.value, 0)
        }

        try await manager.updateValue(for: propertyId)

        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId)
            XCTAssertEqual(updated.value, 1)
        }

        try await manager.setValue(2, for: propertyId)

        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId)
            XCTAssertEqual(updated.value, 2)
        }

        try await manager.setValue(3, for: propertyId)

        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId)
            XCTAssertEqual(updated.value, 3)
        }

        let range = start...Date()
        let history: [Timestamped<Int>] = try manager.getHistory(for: propertyId, in: range)
        XCTAssertEqual(history.map { $0.value }, [1, 2, 3])
    }

    func testLastValueFromLog() async throws {
        let emitter = MyEmitter()

        let propertyId = PropertyId(owner: emitter.name, uniqueId: 123)

        let manager = PropertyManager(
            logFolder: logFolder,
            serverOwner: emitter)
        emitter.registerAll(with: manager)

        try await manager.setValue(2, for: propertyId)

        let value: Timestamped<Int>? = try manager.loadLastValueFromLog(for: propertyId)
        XCTAssertEqual(value?.value, 2)
    }
}
