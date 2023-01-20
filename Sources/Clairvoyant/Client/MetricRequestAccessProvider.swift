import Foundation

public protocol MetricRequestAccessProvider {

    func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest)
}

