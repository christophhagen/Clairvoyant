import Foundation

public enum PropertyError: Error {
    case unknownProperty
    case unknownOwner
    case actionNotPermitted
    case inconsistentData
    case initializationFailed
    case authenticationFailed
    case failedToDecode
    case failedToEncode
}
