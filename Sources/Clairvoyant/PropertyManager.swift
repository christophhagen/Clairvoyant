import Foundation
import CBORCoding
#if canImport(Vapor)
import Vapor
#endif

private let encoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970)
private let decoder = CBORDecoder()

/**
 Decode a value using the common decoder.
 - Throws: `PropertyError.failedToDecode`
 */
private func decode<T>(from data: Data) throws -> T where T: Decodable {
    do {
        return try decoder.decode(from: data)
    } catch {
        throw PropertyError.failedToDecode
    }
}

/**
 Encode a value using the common encoder.
 - Throws: `PropertyError.failedToEncode`
 */
private func encode<T>(_ value: T) throws -> Data where T: Encodable {
    do {
        return try encoder.encode(value)
    } catch {
        throw PropertyError.failedToEncode
    }
}

/**
 
 */
public final class PropertyManager {

    /**
     Create a property manager to expose monitored properties and update them.
     */
    public init(logFolder: URL, serverOwner: ServerOwner) {
        self.logFolder = logFolder
        self.status = .init(value: .neverReported)
        self.serverOwner = serverOwner
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
        closeStatusHandle()
    }

    private let logFolder: URL

    private var properties: [PropertyId : PropertyReference] = [:]

    private var owners: [String : PropertyOwner] = [:]

    private var performPeriodicPropertyUpdates = false

    private var status: Timestamped<ServerStatus>

    private var statusHandle: FileHandle?

    private let serverOwner: ServerOwner

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
                return try encode(value)
            }
        }
        if let write = property.write {
            details.write = { [weak self] data in
                let value: T = try decode(from: data)
                try await write(value)
                if details.isLogged {
                    let t = Timestamped(value: value)
                    let data = try encode(t)
                    self?.log(data, for: id)
                }
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

    func getStatus(accessData: Data) throws -> Timestamped<ServerStatus> {
        guard serverOwner.hasStatusAccess(with: accessData) else {
            throw PropertyError.authenticationFailed
        }
        return status
    }

    func getOwnerList(accessData: Data) throws -> [String] {
        guard serverOwner.hasOwnerListAccess(with: accessData) else {
            throw PropertyError.authenticationFailed
        }
        return owners.map { $0.key }
    }

    func getPropertyList(for ownerName: String, accessData: Data) throws -> [PropertyDescription] {
        guard let owner = owners[ownerName] else {
            throw PropertyError.unknownProperty
        }
        guard owner.hasListAccessPermission(accessData) else {
            throw PropertyError.authenticationFailed
        }
        return properties.filter { $0.key.name == ownerName }.map {
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
        return try decode(from: data)
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

    // MARK: Status

    public func update(status: ServerStatus) {
        self.status = status.timestamped()
        do {
            let fileHandle = try getStatusHandle()
            let data = try encoder.encode(self.status)
            try append(data, withLengthInformationTo: fileHandle)
        } catch {
            print("Failed to log status: \(error)")
            closeStatusHandle()
        }
    }

    // MARK: Routes

#if canImport(Vapor)
    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "properties") {
        app.post(subPath, "status") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let accessData = try request.token()
            return try self.getStatus(accessData: accessData)
        }

        app.post(subPath, "status", "history") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            guard let body = request.body.data?.all() else {
                throw Abort(.badRequest)
            }
            let range: ClosedRange<Date> = try decoder.decode(from: body)

            let accessData = try request.token()
            return try self.getStatusHistory(in: range, accessData: accessData)
        }

        app.post(subPath, "owners") { [weak self] request async throws in
            guard let self else {
                throw Abort(.internalServerError)
            }

            let accessData = try request.token()
            return try self.getOwnerList(accessData: accessData)
        }

        app.post(subPath, ":owner", "list") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }
            guard let owner = request.parameters.get("owner", as: String.self) else {
                throw Abort(.badRequest)
            }

            let accessData = try request.token()
            return try self.getPropertyList(for: owner, accessData: accessData)
        }

        app.post(subPath, "get", ":owner", ":id") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            guard let owner = request.parameters.get("owner", as: String.self),
                  let id = request.parameters.get("id", as: UInt32.self) else {
                throw Abort(.badRequest)
            }
            let parameterId = PropertyId(name: owner, uniqueId: id)

            let accessData = try request.token()
            return try await self.getValue(for: parameterId, accessData: accessData)
        }

        app.post(subPath, "set", ":owner", ":id") { [weak self] request -> Void in
            guard let self else {
                throw Abort(.internalServerError)
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
        }

        app.post(subPath, "history") { [weak self] request in
            guard let self else {
                throw Abort(.internalServerError)
            }

            guard let body = request.body.data?.all() else {
                throw Abort(.badRequest)
            }

            let historyRequest: PropertyHistoryRequest = try decoder.decode(from: body)
            let property = PropertyId(name: historyRequest.owner, uniqueId: historyRequest.propertyId)

            let accessData = try request.token()
            return try self.getHistory(for: property, in: historyRequest.range, accessData: accessData)
        }
    }
#endif

    // MARK: Logging

    private var statusLogUrl: URL {
        logFolder.appendingPathComponent("status")
    }

    private func getStatusHandle() throws -> FileHandle {
        if let statusHandle {
            return statusHandle
        }
        let handle = try createFileHandle(at: statusLogUrl)
        statusHandle = handle
        return handle
    }

    private func closeStatusHandle() {
        do {
            try statusHandle?.close()
        } catch {
            print("Failed to close status log file: \(error)")
        }
        statusHandle = nil
    }

    private func logFileUrl(for property: PropertyId) -> URL {
        logFolder
            .appendingPathComponent(property.name)
            .appendingPathComponent(String(property.uniqueId))
    }

    private func log(_ value: Data, for property: PropertyId) {
        properties[property]?.lastValue = value
        do {
            let handle = try fileHandle(for: property)
            try append(value, withLengthInformationTo: handle)
        } catch {
            print("Failed to log property \(property): \(error)")
            closeFileHandle(for: property)
        }
    }

    private func append(_ value: Data, withLengthInformationTo fileHandle: FileHandle) throws {
        let length = UInt32(value.count).toData()
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: length + value)
        try fileHandle.synchronize()
    }

    private func fileHandle(for property: PropertyId) throws -> FileHandle {
        if let handle = properties[property]?.fileHandle {
            return handle
        }
        let url = logFileUrl(for: property)
        let handle = try createFileHandle(at: url)
        properties[property]?.fileHandle = handle
        return handle
    }

    private func closeFileHandle(for property: PropertyId) {
        guard let handle = properties[property]?.fileHandle else {
            return
        }
        do {
            try handle.close()
        } catch {
            print("Failed to close log file: \(error)")
        }
        properties[property]?.fileHandle = nil
    }

    private func createFileHandle(at url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let handle = try FileHandle(forUpdating: url)
        return handle
    }

    public func deleteLogfile(for property: PropertyId) throws {
        try properties[property]?.fileHandle?.close()
        properties[property]?.fileHandle = nil
        let url = logFileUrl(for: property)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func getHistory(for id: PropertyId, in range: ClosedRange<Date>, accessData: Data) throws -> Data {
        guard properties[id] != nil else {
            throw PropertyError.unknownProperty
        }
        guard let owner = owners[id.name] else {
            throw PropertyError.unknownProperty
        }
        guard owner.hasReadPermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        let handle = try fileHandle(for: id)
        do {
            return try getHistory(at: handle, in: range)
        } catch {
            closeFileHandle(for: id)
            throw error
        }
    }

    public func getStatusHistory(in range: ClosedRange<Date>, accessData: Data) throws -> Data {
        let handle = try getStatusHandle()
        do {
            return try getHistory(at: handle, in: range)
        } catch {
            closeStatusHandle()
            throw error
        }
    }

    private func getHistory(at handle: FileHandle, in range: ClosedRange<Date>) throws -> Data {
        try handle.seek(toOffset: 0)
        var result = Data()
        while true {
            guard let byteCountData = try handle.read(upToCount: 4) else {
                break
            }
            guard let byteCount = UInt32(fromData: byteCountData) else {
                print("Not a valid byte count")
                break
            }
            guard let valueData = try handle.read(upToCount: Int(byteCount)) else {
                print("No more bytes for value (needed \(byteCount))")
                break
            }
            let abstractValue: AnyTimestamped = try decode(from: valueData)
            if range.contains(abstractValue.timestamp) {
                result.append(byteCountData + valueData)
            }
        }
        return result
    }

    public func getHistory<T>(for id: PropertyId, in range: ClosedRange<Date>, accessData: Data) throws -> [Timestamped<T>] where T: PropertyValueType {
        let data = try getHistory(for: id, in: range, accessData: accessData)
        var result = [Timestamped<T>]()
        var index = data.startIndex
        while true {
            guard index + 4 <= data.endIndex else {
                break
            }

            let byteCount = Int(UInt32(fromData: data[index..<index+4])!)
            index += 4
            guard index + byteCount <= data.endIndex else {
                print("No more bytes for data (Needed \(byteCount), \(data.endIndex - index) remaining)")
                break
            }
            let valueData = data[index..<index+byteCount]
            index += byteCount
            let value: Timestamped<T> = try decoder.decode(from: valueData)
            result.append(value)
        }
        return result
    }
}
