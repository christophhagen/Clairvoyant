import Foundation

public enum PropertyAuthenticationMethod {

    /// All properties can be accessed by everyone
    case none

    /// An authentication token is required
    case accessToken

    /// A signature is required
    case publicKey

}
