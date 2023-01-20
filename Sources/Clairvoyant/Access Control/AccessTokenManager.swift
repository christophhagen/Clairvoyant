import Foundation

public final class AccessTokenManager: MetricAccessManager {

    private var tokens: Set<AccessToken>

    public init(_ tokens: Set<AccessToken>) {
        self.tokens = tokens
    }

    public func add(_ token: AccessToken) {
        tokens.insert(token)
    }

    public func remove(_ token: AccessToken) {
        tokens.remove(token)
    }

    public func metricListAccess(isAllowedForToken accessToken: AccessToken) throws {
        guard tokens.contains(accessToken) else {
            throw MetricError.accessDenied
        }
    }

    public func metricAccess(to metric: MetricId, isAllowedForToken accessToken: AccessToken) throws {
        guard tokens.contains(accessToken) else {
            throw MetricError.accessDenied
        }
    }
}
