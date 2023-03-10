import Foundation
import Vapor

public protocol MetricRequestAccessManager {

    func metricListAccess(isAllowedForRequest request: Request) throws

    func metricAccess(to metric: MetricId, isAllowedForRequest request: Request) throws
}
