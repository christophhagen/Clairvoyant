import Foundation

public protocol MetricValue: Timestampable, Codable, Equatable {

    /**
     The metric type.

     Describes the metric, to enable decoding of abstract properties (except complex types)
     */
    static var valueType: MetricType { get }
}

extension MetricValue {

    /**
     The metric type.

     Describes the metric, to enable decoding of abstract properties (except complex types)
     */
    var valueType: MetricType {
        Self.valueType
    }
}

public protocol CustomMetricValue: MetricValue {
    
    static var customTypeName: String { get }
}

extension CustomMetricValue {
    
    public static var valueType: MetricType {
        .customType(named: customTypeName)
    }
}
