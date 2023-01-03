import XCTest
import Clairvoyant
import CBORCoding

final class MyEmitter: PropertyOwner {

    let name = "MyEmitter"

    var value: Timestamped<Int>

    init() {
        self.value = .init(value: 0)
    }

    var authenticationMethod: Clairvoyant.PropertyAuthenticationMethod {
        .accessToken
    }

    let hasPublicPropertyList = true

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

    func test() async throws {
        let emitter = MyEmitter()

        let manager = PropertyManager(logFolder: temporaryDirectory.appendingPathComponent("logs"))
        emitter.registerAll(with: manager)

        let propertyId = PropertyId(name: emitter.name, uniqueId: 123)
        let accessData = Data()
        let decoder = CBORDecoder()
        let encoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970)

        do {
            let initial = try await manager.getValue(for: propertyId, accessData: accessData)
            let decoded: Timestamped<Int> = try decoder.decode(from: initial)
            XCTAssertEqual(decoded.value, 0)
        }

        try await manager.updateValue(for: propertyId, accessData: accessData)

        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId, accessData: accessData)
            XCTAssertEqual(updated.value, 1)
        }
        do {
            let data = try encoder.encode(2)
            try await manager.setValue(data, for: propertyId, accessData: accessData)
        }
        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId, accessData: accessData)
            XCTAssertEqual(updated.value, 2)
        }

        try await manager.setValue(3, for: propertyId, accessData: accessData)
        do {
            let updated: Timestamped<Int> = try await manager.getValue(for: propertyId, accessData: accessData)
            XCTAssertEqual(updated.value, 3)
        }

    }
}
