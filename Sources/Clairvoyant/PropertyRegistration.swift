import Foundation

public typealias PropertyReadCallback<T> = () async throws -> Timestamped<T>
public typealias PropertyWriteCallback<T> = (T) async throws -> Void
public typealias PropertyUpdateCallback<T> = () async throws -> Timestamped<T>

public struct PropertyRegistration<T> where T: PropertyValueType {

    public let uniqueId: UInt32

    public let name: String

    public let updates: PropertyUpdate<T>

    public let isLogged: Bool

    public let allowsManualUpdate: Bool

    public let read: PropertyReadCallback<T>?

    public let write: PropertyWriteCallback<T>?

    public init(uniqueId: UInt32, name: String, updates: PropertyUpdate<T> = .none, isLogged: Bool = false, allowsManualUpdate: Bool = false, read: PropertyReadCallback<T>? = nil, write: PropertyWriteCallback<T>? = nil) {
        self.uniqueId = uniqueId
        self.name = name
        self.updates = updates
        self.isLogged = isLogged
        self.allowsManualUpdate = allowsManualUpdate
        self.read = read
        self.write = write
    }

    public init(id: PropertyId, name: String, type: T.Type, on server: URL, authentication: RemotePropertyAuthentication, isWritable: Bool, isReadable: Bool, isLogged: Bool = false, updateInterval: TimeInterval? = nil, allowsManualUpdate: Bool = false, serverToPush: URL? = nil) {
        self.uniqueId = id.uniqueId
        self.name = name
        if let updateInterval {
            self.updates = .interval(updateInterval) {
                try await PropertyManager.collect(id, from: server, auth: authentication)
            }
        } else if allowsManualUpdate {
            self.updates = .manual {
                try await PropertyManager.collect(id, from: server, auth: authentication)
            }
        } else {
            self.updates = .none
        }
        self.isLogged = isLogged
        self.allowsManualUpdate = allowsManualUpdate
        if isReadable {
            self.read = {
                try await PropertyManager.collect(id, from: server, auth: authentication)
            }
        } else {
            self.read = nil
        }
        if isWritable {
            self.write = { value in
                try await PropertyManager.set(value, for: id, on: server, auth: authentication)
            }
        } else {
            self.write = nil
        }
        self.push = serverToPush
    }

    var isUpdating: Bool {
        updates.isUpdating
    }
}
