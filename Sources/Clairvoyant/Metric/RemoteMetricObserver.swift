import Foundation

public typealias AccessToken = Data

public struct RemoteMetricObserver: Equatable, Hashable {

    /**
     The url of the remote server.

     The url only contains the common part of the metrics API,
     e.g. the url where the Vapor instance is running,
     plus the subPath passed to `registerRoutes(_:,subPath:)` on the remote server.
     */
    public let remoteUrl: URL

    /// The provider of the authentication required to access the remote server
    let authenticationToken: AccessToken

    public init(remoteUrl: URL, authenticationToken: AccessToken) {
        self.remoteUrl = remoteUrl
        self.authenticationToken = authenticationToken
    }
}
