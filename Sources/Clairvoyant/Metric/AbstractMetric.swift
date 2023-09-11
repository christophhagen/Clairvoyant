import Foundation

protocol AbstractMetric: AnyObject, GenericMetric {

    /**
     The info of the metric.
     */
    var info: MetricInfo { get }
}
