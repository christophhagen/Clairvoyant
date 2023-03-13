import Foundation

public struct MetricAccessToken: MetricAccessTokenProvider {

    public let accessToken: Data

    public init(accessToken: Data) {
        self.accessToken = accessToken
    }

    public init?(base64String: String) {
        guard let accessToken = Data(base64Encoded: base64String) else {
            return nil
        }
        self.accessToken = accessToken
    }

    public init(string: String) {
        self.accessToken = string.data(using: .utf8)!
    }

    public var base64: String {
        accessToken.base64EncodedString()
    }
}

extension MetricAccessToken: Hashable {
    
}
