import Foundation

public protocol ServerOwner: PropertyOwner {

}

public extension ServerOwner {

    /// The property owner name of the server
    var name: String { "Server" }
}
