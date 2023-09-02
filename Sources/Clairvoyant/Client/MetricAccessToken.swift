import Foundation

public struct MetricAccessToken: MetricAccessTokenProvider {
    
    public let base64: String
    
    public init(base64: String) {
        self.base64 = base64
    }
    
    public init(accessToken: Data) {
        self.base64 = accessToken.base64EncodedString()
    }
    
    
    public init(string: String) {
        self.init(accessToken: string.data(using: .utf8)!)
    }
}

extension MetricAccessToken: Hashable {
    
}
