import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol MetricRequestAccessProvider {

    func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest)
}

