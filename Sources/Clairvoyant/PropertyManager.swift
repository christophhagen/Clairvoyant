import Foundation
import CBORCoding
import Vapor

private let encoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970)
private let decoder = CBORDecoder()

/**
 
 */
public final class PropertyManager {

    /**
     Create a property manager to expose monitored properties and update them.
     */
    public init(logFolder: URL) {
        self.logFolder = logFolder
    }

    deinit {
        properties.values.forEach { property in
            guard let handle = property.fileHandle else {
                return
            }
            do {
                try handle.close()
            } catch {
                print("Failed to close log file: \(error)")
            }
        }
    }

    private let logFolder: URL

    private var properties: [PropertyId : PropertyReference] = [:]

    private var owners: [String : PropertyOwner] = [:]

    private var performPeriodicPropertyUpdates = false

    // MARK: Registration

    /**
     Register a property for monitoring.

     This function fails (returns `false`) if one of the following conditions occurs:
     - The property has both `read` and `write` set to `nil`
     - The property has `allowsManualUpdate = true` and `update = .continuous`

     - Parameter property: The information about the property
     - Parameter source: The owner of the property
     - Returns: `true`, if the property was registered, `false`, if an error occured.
     */
    @discardableResult
    public func register<T>(_ property: PropertyRegistration<T>, for source: PropertyOwner) -> Bool {
        guard property.read != nil || property.write != nil else {
            return false
        }
        if property.allowsManualUpdate && !property.isUpdating {
            return false
        }
        let id = PropertyId(name: source.name, uniqueId: property.uniqueId)
        guard properties[id] == nil else {
            return false
        }
        var details = PropertyReference(
            name: property.name,
            type: T.type,
            update: .continuous,
            isLogged: property.isLogged,
            allowsManualUpdate: property.allowsManualUpdate)
        if let read = property.read {
            details.read = {
                let value = try await read()
                return try encoder.encode(value)
            }
        }
        if let write = property.write {
            details.write = { data in
                let value: T = try decoder.decode(from: data)
                try await write(value)
            }
        }
        switch property.updates {
        case .continuous, .none:
            break
        case .interval(let interval, let closure):
            details.update = .interval(interval, makeUpdateAndLoggingClosure(closure, for: id))
        case .manual(let closure):
            details.update = .manual(makeUpdateAndLoggingClosure(closure, for: id))

        }
        properties[id] = details
        owners[source.name] = source
        return true
    }

    // MARK: Property access

    func getPropertyList() -> [String : [PropertyDescription]] {
        owners.keys.reduce(into: [:]) { list, owner in
            list[owner] = getPropertyList(for: owner)
        }
    }

    func getPropertyList(for owner: String) -> [PropertyDescription] {
        properties.filter { $0.key.name == owner }.map {
            $0.value.description(uniqueId: $0.key.uniqueId)
        }
    }

    public func getValue(for id: PropertyId, accessData: Data) async throws -> Data {
        guard let property = properties[id] else {
            throw PropertyError.unknownProperty
        }
        guard let read = property.read else {
            throw PropertyError.actionNotPermitted
        }
        guard let owner = owners[id.name] else {
            throw PropertyError.unknownProperty
        }
        guard owner.hasReadPermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        return try await read()
    }

    public func getValue<T>(for id: PropertyId, accessData: Data) async throws -> Timestamped<T> where T: PropertyValueType {
        let data = try await getValue(for: id, accessData: accessData)
        return try decoder.decode(from: data)
    }

    public func setValue(_ value: Data, for id: PropertyId, accessData: Data) async throws {
        guard let property = properties[id] else {
            throw PropertyError.unknownProperty
        }
        guard let write = property.write else {
            throw PropertyError.actionNotPermitted
        }
        guard let owner = owners[id.name] else {
            throw PropertyError.unknownProperty
        }
        guard owner.hasWritePermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        try await write(value)
    }

    public func setValue<T>(_ value: T, for id: PropertyId, accessData: Data) async throws where T: PropertyValueType {
        let data = try encoder.encode(value)
        try await setValue(data, for: id, accessData: accessData)
    }

    public func updateValue(for id: PropertyId, accessData: Data) async throws {
        guard let property = properties[id] else {
            throw PropertyError.unknownProperty
        }
        guard let update = property.update.updateCallback else {
            throw PropertyError.actionNotPermitted
        }
        guard let owner = owners[id.name] else {
            throw PropertyError.unknownProperty
        }
        guard owner.hasReadPermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        try await update()
    }

    // MARK: Updates

    private func makeUpdateAndLoggingClosure<T>(_ update: @escaping PropertyUpdateCallback<T>, for property: PropertyId) -> AbstractPropertyUpdate where T: PropertyValueType {
        return { [weak self] in
            let value = try await update()
            let encoded = try encoder.encode(value)
            guard let lastValueData = self?.lastValue(for: property) else {
                self?.log(encoded, for: property)
                return
            }
            let lastValue: Timestamped<T>? = try decoder.decode(from: lastValueData)
            if lastValue?.value != value?.value {
                self?.log(encoded, for: property)
            }
        }
    }

    private func lastValue(for property: PropertyId) -> Data? {
        properties[property]?.lastValue
    }

    public func startPeriodicPropertyUpdates(priority: TaskPriority? = nil) {
        guard !performPeriodicPropertyUpdates else {
            // Periodic updates are already running
            return
        }
        performPeriodicPropertyUpdates = true
        Task(priority: priority) {
            while true {
                let nextUpdate = await performRoundOfPropertyUpdates()
                guard performPeriodicPropertyUpdates else {
                    return
                }
                let delay = nextUpdate.timeIntervalSinceNow
                guard delay > 0 else {
                    continue
                }
                guard delay < Double(UInt64.max) else {
                    print("Very large delay (\(delay) s), quitting updates")
                    return
                }
                await Task.yield()
                let delayNS = UInt64(delay * 1000_000_000)
                try await Task.sleep(nanoseconds: delayNS)
            }
        }
    }

    public func endPeriodicPropertyUpdates() {
        performPeriodicPropertyUpdates = false
    }

    private func performRoundOfPropertyUpdates() async -> Date {
        var nextUpdate = Date.distantFuture
        for (id, property) in properties  {
            guard performPeriodicPropertyUpdates else {
                return .distantFuture
            }
            guard case let .interval(interval, update) = property.update else {
                continue
            }
            let now = Date()
            let next = property.nextUpdate ?? now
            if next > now {
                nextUpdate = min(nextUpdate, next)
                continue
            }
            do {
                try await update()
            } catch {
                print("Failed to update property \(property.name): \(error)")
            }
            properties[id]?.didUpdate()
            nextUpdate = min(nextUpdate, next.advanced(by: interval))
        }
        return nextUpdate
    }

    // MARK: Routes

    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "properties") {
        app.post(.constant(subPath), "list") { [weak self] request async throws -> Response in
            guard let self else {
                return .init(status: .internalServerError)
            }

            let list = self.getPropertyList()
            let data = try encoder.encode(list)
            return .init(status: .ok, body: .init(data: data))
        }

        app.post(.constant(subPath), ":owner", "list") { [weak self] request async throws -> Response in
            guard let self else {
                return .init(status: .internalServerError)
            }
            guard let owner = request.parameters.get("owner", as: String.self) else {
                throw Abort(.badRequest)
            }
            let list = self.getPropertyList(for: owner)
            let data = try encoder.encode(list)
            return .init(status: .ok, body: .init(data: data))
        }

        app.post(.constant(subPath), "get", ":owner", ":id") { [weak self] request async throws -> Response in
            guard let self else {
                return .init(status: .internalServerError)
            }

            guard let owner = request.parameters.get("owner", as: String.self),
                  let id = request.parameters.get("id", as: UInt32.self) else {
                throw Abort(.badRequest)
            }
            let parameterId = PropertyId(name: owner, uniqueId: id)

            let accessData = try request.token()
            let data = try await self.getValue(for: parameterId, accessData: accessData)
            return .init(status: .ok, body: .init(data: data))
        }

        app.post(.constant(subPath), "set", ":owner", ":id") { [weak self] request async throws -> Response in
            guard let self else {
                return .init(status: .internalServerError)
            }

            guard let owner = request.parameters.get("owner", as: String.self),
                  let id = request.parameters.get("id", as: UInt32.self) else {
                throw Abort(.badRequest)
            }
            let parameterId = PropertyId(name: owner, uniqueId: id)

            let accessData = try request.token()

            guard let value = request.body.data?.all() else {
                throw Abort(.badRequest)
            }
            try await self.setValue(value, for: parameterId, accessData: accessData)
            return .init(status: .ok)
        }
    }

    // MARK: Logging

    private func logFileUrl(for property: PropertyId) -> URL {
        logFolder
            .appendingPathComponent(property.name)
            .appendingPathComponent(String(property.uniqueId))
    }

    private func log(_ value: Data, for property: PropertyId) {
        properties[property]?.lastValue = value
        do {
            let handle = try fileHandle(for: property)
            try handle.seekToEnd()
            let length = UInt32(value.count).toData()
            try handle.write(contentsOf: length + value)
        } catch {
            print("Failed to log property \(property): \(error)")
        }
    }

    private func fileHandle(for property: PropertyId) throws -> FileHandle {
        if let handle = properties[property]?.fileHandle {
            return handle
        }
        let url = logFileUrl(for: property)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forUpdating: url)
        properties[property]?.fileHandle = handle
        return handle
    }
}

extension ByteBuffer {

    func all() -> Data? {
        getData(at: 0, length: readableBytes)
    }
}

private extension Request {

    func token() throws -> Data {
        guard let string = headers.first(name: "token") else {
            return Data()
        }
        guard let data = Data(base64Encoded: string) else {
            throw Abort(.badRequest)
        }
        return data
    }
}
