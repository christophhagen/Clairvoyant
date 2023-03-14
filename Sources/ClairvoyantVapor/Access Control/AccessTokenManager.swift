import Foundation
import Clairvoyant

/**
A very simple access control manager to protect observed metrics.

 Some form of access manager is required for each metric observer.
 ```
 let manager = AccessTokenManager(...)
 let observer = MetricObserver(logFolder: ..., accessManager: manager, logMetricId: ...)
 ```
 */
public final class AccessTokenManager: MetricAccessManager {

    private var tokens: Set<MetricAccessToken>

    /**
     Create a new manager with a set of access tokens.
     - Parameter tokens: The access tokens which should have access to the metrics
     */
    public init<T>(_ tokens: T) where T: Sequence<MetricAccessToken> {
        self.tokens = Set(tokens)
    }

    /**
     Add a new access token.
     - Parameter token: The access token to add.
     */
    public func add(_ token: MetricAccessToken) {
        tokens.insert(token)
    }

    /**
     Remove an access token.
     - Parameter token: The access token to remove.
     */
    public func remove(_ token: MetricAccessToken) {
        tokens.remove(token)
    }

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter token: The access token provided in the request.
     - Throws: `MetricError.accessDenied`
     */
    public func metricListAccess(isAllowedForToken accessToken: MetricAccessToken) throws {
        guard tokens.contains(accessToken) else {
            throw MetricError.accessDenied
        }
    }

    /**
     Check if a provided token exists in the token set to allow access.
     - Parameter metric: The id of the metric for which access is requested.
     - Parameter token: The access token provided in the request.
     - Throws: `MetricError.accessDenied`
     */
    public func metricAccess(to metric: MetricId, isAllowedForToken accessToken: MetricAccessToken) throws {
        guard tokens.contains(accessToken) else {
            throw MetricError.accessDenied
        }
    }
}
