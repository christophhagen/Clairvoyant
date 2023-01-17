import Foundation
import Crypto

struct InternalMetricId: AbstractMetric {

    let id: MetricId

    let idHash: MetricIdHash

    init(id: MetricId) {
        self.id = id
        self.idHash = InternalMetricId.hash(id)
    }

    // MARK: Helper

    static func hash(_ id: MetricId) -> MetricIdHash {
        SHA256.hash(data: id.data(using: .utf8)!).prefix(16).hex
    }
}
