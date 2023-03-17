//
//  File.swift
//  
//
//  Created by CH on 17.03.23.
//

import Foundation
import Clairvoyant
import CBORCoding

public extension MetricObserver {

    /**
     Create a new observer.

     Each observer creates a metric with the id `logMetricId` to log internal errors.
     It is also possible to write to this metric using ``log(_:)``.

     - Parameter logFolder: The directory where the log files and other internal data is to be stored.
     - Parameter logMetricId: The id of the metric for internal log data
     - Parameter logMetricName: A name for the logging metric
     - Parameter logMetricDescription: A textual description of the logging metric
     - Parameter encoder: The encoder to use for log files
     - Parameter decoder: The decoder to use for log files
     - Parameter fileSize: The maximum size of files in bytes
     */
    convenience init(
        logFileFolder: URL,
        logMetricId: String,
        logMetricName: String? = nil,
        logMetricDescription: String? = nil,
        encoder: BinaryEncoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970),
        decoder: BinaryDecoder = CBORDecoder(),
        fileSize: Int = 10_000_000) {
            self.init(
                logFolder: logFileFolder,
                logMetricId: logMetricId,
                logMetricName: logMetricName,
                logMetricDescription: logMetricDescription,
                encoder: encoder,
                decoder: decoder,
                fileSize: fileSize)
        }
}
