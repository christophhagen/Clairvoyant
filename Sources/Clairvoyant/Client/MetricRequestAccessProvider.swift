import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 A generic type to add access control information to outgoing requests.
 */
public protocol MetricRequestAccessProvider {

    /**

     */
    func addAccessDataToMetricRequest(_ metricRequest: inout URLRequest, route: ServerRoute)
}

