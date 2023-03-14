import Foundation

public protocol GenericMetric {

    /**
     The unique id of the metric.

     The id should be globally unique, so that there are no conflicts when metrics from multiple systems are collected
     */
    var id: MetricId { get }

    var canBeUpdatedByRemote: Bool { get }

    func lastValueData() async -> Data?

    func update(_ dataPoint: Data) async throws

    func history(from startDate: Date, to endDate: Date, maximumValueCount: Int?) async -> Data
}
