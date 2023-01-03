import Foundation

public protocol PropertyOwner {

    /// The name of the property owner (service, server, application, ...)
    var name: String { get }

    /// The type of authentication required to access properties
    var authenticationMethod: PropertyAuthenticationMethod { get }

    /// The property list can be viewed by anyone without requiring permission
    var hasPublicPropertyList: Bool { get }

    func hasReadPermission(for property: UInt32, accessData: Data) -> Bool

    func hasWritePermission(for property: UInt32, accessData: Data) -> Bool
}
