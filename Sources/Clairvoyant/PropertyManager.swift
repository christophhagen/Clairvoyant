import Foundation
import CBORCoding
#if canImport(Vapor)
import Vapor
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
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

    /// The property id for the server log file
    public let serverLogPropertyId: PropertyId!

    /// The property id for the server status
    public let serverStatusPropertyId: PropertyId!

    /**
     Create a property manager to expose monitored properties and update them.
     - Parameter logFolder: The folder where property logs are stored
     - Parameter serverOwner: The instance controlling access to the main server properties
     - Note: This function registers two properties for the server owner: The generic log file for internal errors (`id = 0`) and the server status (`id = 1`).
     The server status can be updated using `update(status:)`, while the log entries can be added using `log(_:)` on the property manager.
     */
    public init(logFolder: URL, serverOwner: ServerOwner) {
        self.logFolder = logFolder
        self.serverOwner = serverOwner
        self.serverLogPropertyId = .init(owner: serverOwner.name, uniqueId: 0)
        self.serverStatusPropertyId = .init(owner: serverOwner.name, uniqueId: 1)

        let logProperty = PropertyRegistration(
            uniqueId: 0,
            name: serverOwner.name,
            isLogged: true,
            read: { [weak self] in
                self?.lastLogMessage ?? "".timestamped()
            })
         register(logProperty, for: serverOwner)

        let statusProperty = PropertyRegistration(
            uniqueId: 1,
            name: serverOwner.name,
            isLogged: true,
            read: { [weak self] in
                self?.lastServerStatus ?? .init(value: .neverReported)
            })
        register(statusProperty, for: serverOwner)
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

    /// The url to the folder where the log files are stored
    private let logFolder: URL

    /// The internal list of properties, indexed by their ids.
    private var properties: [PropertyId : PropertyReference] = [:]

    /// The known property owners, indexed by their name
    private var owners: [String : PropertyOwner] = [:]

    /// The internal flag indicating that property updates are being performed regularly
    private var performPeriodicPropertyUpdates = false

    /// The instance controlling access to the property owner list
    private let serverOwner: ServerOwner

    /// The last logged message
    private var lastLogMessage: Timestamped<String> = .init(value: "Log started")

    /// The last server status
    private var lastServerStatus: Timestamped<ServerStatus> = .init(value: .neverReported)

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
    public func register<T>(_ property: PropertyRegistration<T>, for source: PropertyOwner) -> PropertyId? {
        guard property.read != nil || property.write != nil else {
            return nil
        }
        if property.allowsManualUpdate && !property.isUpdating {
            return nil
        }
        let id = PropertyId(owner: source.name, uniqueId: property.uniqueId)
        guard properties[id] == nil else {
            return nil
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
            details.update = .interval(interval, makeUpdateClosure(closure, for: id, isLogged: property.isLogged))
        case .manual(let closure):
            details.update = .manual(makeUpdateClosure(closure, for: id, isLogged: property.isLogged))

        }
        if property.isLogged, let lastValue = try? loadLastValueDataFromLog(for: id) {
            details.lastValue = lastValue
        }
        properties[id] = details
        owners[source.name] = source
        return id
    }

    static func collect<T>(_ property: PropertyId, from server: URL, auth: RemotePropertyAuthentication) async throws -> Timestamped<T> where T: PropertyValueType {
        let url = server.appendingPathComponent("get/\(property.owner)/\(property.uniqueId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        switch auth {
        case .none:
            break
        case .authToken(let token):
            request.addValue(token.base64EncodedString(), forHTTPHeaderField: "token")
        case .privateKey(_):
            // TODO: Allow access with public key signature
            break
        }

        let data: Data
        let response: URLResponse
        do {
#if canImport(FoundationNetworking)
            (data, response) = try await urlSessionData(URLSession.shared, for: request)
#else
            (data, response) = try await URLSession.shared.data(for: request)
#endif
        } catch {
            throw PropertyError.remoteServerRequestFailed
        }
        guard let response = (response as? HTTPURLResponse) else {
            throw PropertyError.remoteServerRequestFailed
        }
        if response.statusCode == 404 {
            throw PropertyError.remotePropertyNotFound
        }
        guard response.statusCode == 200 else {
            throw PropertyError.remoteServerRequestFailed
        }
        return try decode(from: data)
    }

    static func set<T>(_ value: T, for property: PropertyId, on server: URL, auth: RemotePropertyAuthentication) async throws where T: PropertyValueType {
        let url = server.appendingPathComponent("set/\(property.owner)/\(property.uniqueId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encode(value)
        switch auth {
        case .none:
            break
        case .authToken(let token):
            request.addValue(token.base64EncodedString(), forHTTPHeaderField: "token")
        case .privateKey(_):
            // TODO: Allow access with public key signature
            break
        }

        let response: URLResponse
        do {
#if canImport(FoundationNetworking)
            (_, response) = try await urlSessionData(URLSession.shared, for: request)
#else
            (_, response) = try await URLSession.shared.data(for: request)
#endif
        } catch {
            throw PropertyError.remoteServerRequestFailed
        }
        guard let response = (response as? HTTPURLResponse) else {
            throw PropertyError.remoteServerRequestFailed
        }
        if response.statusCode == 404 {
            throw PropertyError.remotePropertyNotFound
        }
        if response.statusCode != 200 {
            throw PropertyError.remoteServerRequestFailed
        }
    }

    // MARK: Status

    /**
     Update the server status.

     The server status is logged and accessible using the property id, see  ``serverStatusPropertyId``
     - Parameter status: The new server status
     */
    public func update(status: ServerStatus) {
        lastServerStatus = status.timestamped()
        do {
            try logChanged(property: serverStatusPropertyId, value: lastServerStatus)
        } catch {
            // Only encode and decode errors occur here
            log("Failed to update status: \(error)")
        }
    }

    // MARK: Property access

    /**
     Get the owner by name.
     - Parameter name: The name of the owner
     - Throws: `PropertyError.unknownOwner`
     - Returns: The property owner
     */
    private func get(owner name: String) throws -> PropertyOwner {
        try owners[name].unwrap(orThrow: PropertyError.unknownOwner)
    }

    /**
     Get a property by id.
     - Parameter name: The id of the property
     - Throws: `PropertyError.unknownProperty`
     - Returns: The property reference
     */
    private func get(property id: PropertyId) throws -> PropertyReference {
        try properties[id].unwrap(orThrow: PropertyError.unknownProperty)
    }

    /**
     Get the list of all property owners.
     - Parameter accessData: The access data for the server.
     - Throws: `PropertyError.authenticationFailed`
     - Returns: The list of all property owner names
     */
    private func getOwnerList(accessData: Data) throws -> [String] {
        guard serverOwner.hasListAccessPermission(accessData) else {
            throw PropertyError.authenticationFailed
        }
        return owners.map { $0.key }
    }

    /**
     Get the list of properties for an owner.
     - Parameter accessData: The access data for the owner.
     - Throws: `PropertyError.authenticationFailed`
     - Returns: The list of all properties for the owner
     */
    private func getPropertyList(for ownerName: String, accessData: Data) throws -> [PropertyDescription] {
        let owner = try get(owner: ownerName)
        guard owner.hasListAccessPermission(accessData) else {
            throw PropertyError.authenticationFailed
        }
        return properties.filter { $0.key.owner == ownerName }.map {
            $0.value.description(uniqueId: $0.key.uniqueId)
        }
    }

    /**
     Get the data for a property.

     This function is used internally to expose properties over routes.
     - Parameter accessData: The access data for the owner.
     - Throws: `PropertyError.authenticationFailed`, `PropertyError.unknownProperty`, `PropertyError.unknownOwner`, `PropertyError.actionNotPermitted`
     - Returns: The timestamped value of the property, encoded using the standard encoder
     */
    private func getValue(for id: PropertyId, accessData: Data) async throws -> Data {
        guard try get(owner: id.owner).hasReadPermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        return try await getValue(for: id)
    }

    /**
     Access the value of a property.
     - Parameter id: The property id
     - Throws: `PropertyError.unknownProperty`, `PropertyError.actionNotPermitted`
     - Returns: The current value of the property, timestamped
     */
    public func getValue<T>(for id: PropertyId) async throws -> Timestamped<T> where T: PropertyValueType {
        let data = try await getValue(for: id)
        return try decode(from: data)
    }

    private func getValue(for id: PropertyId) async throws -> Data {
        guard let read = try get(property: id).read else {
            throw PropertyError.actionNotPermitted
        }
        return try await read()
    }

    /**
     Set a new value for a property.

     This function is used internally to expose properties over routes.
     - Parameter accessData: The access data for the owner.
     - Parameter data: The data of the property, encoded using the standard encoder
     - Throws: `PropertyError.authenticationFailed`, `PropertyError.unknownProperty`, `PropertyError.unknownOwner`, `PropertyError.actionNotPermitted`, `PropertyError.failedToDecode`
     */
    private func setValue(_ data: Data, for id: PropertyId, accessData: Data) async throws {
        guard try get(owner: id.owner).hasWritePermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        try await setValue(data, for: id)
    }

    private func setValue(_ data: Data, for id: PropertyId) async throws {
        guard let write = try get(property: id).write else {
            throw PropertyError.actionNotPermitted
        }
        try await write(data)
    }

    /**
     Set a new value for a property.

     - Parameter accessData: The access data for the owner.
     - Parameter value: The new value for the property
     - Throws: `PropertyError.authenticationFailed`, `PropertyError.unknownProperty`, `PropertyError.unknownOwner`, `PropertyError.actionNotPermitted`, `PropertyError.failedToEncode`
     */
    public func setValue<T>(_ value: T, for id: PropertyId) async throws where T: PropertyValueType {
        let data = try encode(value)
        try await setValue(data, for: id)
    }

    /**
     Update the value for a property.

     This function is internally used to expose properties over routes.
     */
    func updateValue(for id: PropertyId, accessData: Data) async throws {
        guard try get(owner: id.owner).hasReadPermission(for: id.uniqueId, accessData: accessData) else {
            throw PropertyError.authenticationFailed
        }
        try await updateValue(for: id)
    }

    /**
     Update the value for a property.

     */
    public func updateValue(for id: PropertyId) async throws {
        guard let update = try get(property: id).update.updateCallback else {
            throw PropertyError.actionNotPermitted
        }
        try await update()
    }

    // MARK: Updates

    private func makeUpdateClosure<T>(_ update: @escaping PropertyUpdateCallback<T>, for property: PropertyId, isLogged: Bool) -> AbstractPropertyUpdate where T: PropertyValueType {
        guard isLogged else {
            return { _ = try await update() }
        }
        return { [weak self] in
            let value = try await update()
            try self?.logChanged(property: property, value: value)
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
                    log("Very large delay (\(delay) s), quitting updates")
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
                log("Failed to update property \(property.name): \(error)")
            }
            properties[id]?.didUpdate()
            nextUpdate = min(nextUpdate, next.advanced(by: interval))
        }
        return nextUpdate
    }

    // MARK: Routes

#if canImport(Vapor)
    /**
     Register the routes to access the properties.
     - Parameter subPath: The server route subpath where the properties can be accessed
     */
    public func registerRoutes(_ app: Application, subPath: String = "properties") {

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
            let parameterId = PropertyId(owner: owner, uniqueId: id)

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
            let parameterId = PropertyId(owner: owner, uniqueId: id)

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

            let historyRequest: PropertyHistoryRequest = try request.decodeBody()
            let property = PropertyId(owner: historyRequest.owner, uniqueId: historyRequest.propertyId)

            let accessData = try request.token()
            return try self.getHistory(for: property, in: historyRequest.range, accessData: accessData)
        }
    }
#endif

    // MARK: Logging

    public func logChanged<T>(property propertyId: PropertyId, value: Timestamped<T>) throws where T: PropertyValueType {
        let property = try get(property: propertyId)
        guard property.isLogged else {
            return
        }
        let encoded = try encode(value)
        guard let lastValueData = self.lastValue(for: propertyId) else {
            self.log(encoded, for: propertyId)
            return
        }
        let lastValue: Timestamped<T> = try decode(from: lastValueData)
        if lastValue.value != value.value {
            self.log(encoded, for: propertyId)
        }
    }

    public func log(_ message: String) {
        let value = message.timestamped()
        do {
            try logChanged(property: serverLogPropertyId, value: value)
        } catch {
            print("[] \(message)")
            print("Log failed: \(error)")
        }
    }

    private func logFileUrl(for property: PropertyId) -> URL {
        logFolder
            .appendingPathComponent(property.owner)
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
            log("Failed to close log file: \(error)")
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

    private func getHistory(for id: PropertyId, in range: ClosedRange<Date>, accessData: Data) throws -> Data {
        let owner = try get(owner: id.owner)
        _ = try get(property: id)

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

    private func getHistory(at handle: FileHandle, in range: ClosedRange<Date>) throws -> Data {
        try handle.seek(toOffset: 0)
        var result = Data()
        while let valueData = try handle.getValueDataWithLengthPrepended() {
            let abstractValue: AnyTimestamped = try decode(from: valueData)
            let byteCountData = UInt32(valueData.count).toData()
            if range.contains(abstractValue.timestamp) {
                result.append(byteCountData + valueData)
            }
        }
        return result
    }

    public func getHistory<T>(for id: PropertyId, in range: ClosedRange<Date>) throws -> [Timestamped<T>] where T: PropertyValueType {
        let handle = try fileHandle(for: id)
        try handle.seek(toOffset: 0)
        var result = [Timestamped<T>]()
        while let valueData = try handle.getValueDataWithLengthPrepended() {
            let value: Timestamped<T> = try decode(from: valueData)
            if range.contains(value.timestamp) {
                result.append(value)
            }
        }
        return result
    }

    public func loadLastValueFromLog<T>(for id: PropertyId) throws -> Timestamped<T>? where T: PropertyValueType {
        guard let lastData = try loadLastValueDataFromLog(for: id) else {
            return nil
        }
        let value: Timestamped<T> = try decode(from: lastData)
        return value
    }

    func loadLastValueDataFromLog(for id: PropertyId) throws -> Data? {
        let handle = try fileHandle(for: id)
        try handle.seek(toOffset: 0)
        var lastData: Data?
        while let valueData = try handle.getValueDataWithLengthPrepended() {
            lastData = valueData
        }
        return lastData
    }
}

private extension FileHandle {

    func getValueDataWithLengthPrepended() throws -> Data? {
        guard let byteCountData = try read(upToCount: 4) else {
            return nil
        }
        guard let byteCount = UInt32(fromData: byteCountData) else {
            print("Not a valid byte count")
            throw PropertyError.logFileCorrupted
        }
        guard let valueData = try read(upToCount: Int(byteCount)) else {
            print("No more bytes for value (needed \(byteCount))")
            throw PropertyError.logFileCorrupted
        }
        guard valueData.count == byteCount else {
            print("No more bytes for value (needed \(byteCount))")
            throw PropertyError.logFileCorrupted
        }
        return valueData
    }
}
