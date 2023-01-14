import Foundation

public enum RemotePropertyAuthentication {

    case none

    case authToken(Data)

    case privateKey(Data)
}
