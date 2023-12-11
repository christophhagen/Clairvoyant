import Foundation
import Crypto

public typealias MetricId = String
public typealias MetricIdHash = String

extension MetricIdHash {
    
    static let binaryLength = 16
    
    /// The length of a valid `MetricIdHash`
    public static let hashLength = binaryLength * 2

}

extension MetricId {
    
    public func hashed() -> MetricIdHash {
        SHA256.hash(data: data(using: .utf8)!).prefix(MetricIdHash.binaryLength).hex
    }
}
