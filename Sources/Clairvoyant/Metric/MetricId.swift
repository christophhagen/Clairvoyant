import Foundation
import Crypto

public typealias MetricId = String
public typealias MetricIdHash = String

extension MetricId {

    func hashed() -> MetricIdHash {
        SHA256.hash(data: data(using: .utf8)!).prefix(16).hex
    }
}
