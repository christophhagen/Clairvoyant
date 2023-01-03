import Foundation

public typealias PropertyReadCallback<T> = () async throws -> Timestamped<T>?
public typealias PropertyWriteCallback<T> = (T) async throws -> Void
public typealias PropertyUpdateCallback<T> = () async throws -> Timestamped<T>?

public struct PropertyRegistration<T> where T: PropertyValueType {

    public let uniqueId: UInt32

    public let name: String

    public let updates: PropertyUpdate<T>

    public let isLogged: Bool

    public let allowsManualUpdate: Bool

    public let read: PropertyReadCallback<T>?

    public let write: PropertyWriteCallback<T>?

    public init(uniqueId: UInt32, name: String, updates: PropertyUpdate<T>, isLogged: Bool, allowsManualUpdate: Bool, read: PropertyReadCallback<T>?, write: PropertyWriteCallback<T>?) {
        self.uniqueId = uniqueId
        self.name = name
        self.updates = updates
        self.isLogged = isLogged
        self.allowsManualUpdate = allowsManualUpdate
        self.read = read
        self.write = write
    }
}
