import Foundation

extension Int: MetricValue {

    public static let valueType: MetricType = .integer
}

extension Double: MetricValue {

    public static let valueType: MetricType = .double
}

extension Bool: MetricValue {

    public static let valueType: MetricType = .boolean
}

extension String: MetricValue {

    public static let valueType: MetricType = .string
}

extension Data: MetricValue {

    public static let valueType: MetricType = .data
}

extension Date: MetricValue {
    
    public static let valueType: MetricType = .date
}
