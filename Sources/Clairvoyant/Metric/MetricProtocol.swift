import Foundation

public protocol MetricProtocol {
    
    var info: MetricInfo { get }
}

extension MetricProtocol {
    
    /// The unique name of the metric in the group
    public var id: MetricId { info.id }
    
    /// The group to which this metric belongs
    public var group: String { info.id.group }
    
    /**
     The name to display for the metric.
     
     - Note: This property is **not** updated when it is changed by the metric storage.
     */
    public var name: String? { info.details.name }

    /**
    A description of the metric content
    
     - Note: This property is **not** updated when it is changed by the metric storage.
     */
    public var description: String? { info.details.description }

    /// The additional details of the metric
    public var details: MetricDetails {
        info.details
    }
}
