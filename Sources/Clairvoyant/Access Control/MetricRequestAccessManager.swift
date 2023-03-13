import Foundation
#if canImport(Vapor)
import Vapor

public protocol MetricRequestAccessManager {

    func metricListAccess(isAllowedForRequest request: Request) throws

    func metricAccess(to metric: MetricId, isAllowedForRequest request: Request) throws
}
#else

/**
 Dummy protocol generated when not using Vapor.
 */
public protocol MetricRequestAccessManager {

}
#endif
