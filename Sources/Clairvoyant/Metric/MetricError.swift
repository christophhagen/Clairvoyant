import Foundation

public enum MetricError: UInt8, Error {

    /**
     A value could not be converted to binary data.
     */
    case failedToEncode = 1

    /**
     The log file contains invalid data which could not be decoded.
     */
    case logFileCorrupted = 2

    /**
     The access token was invalid
     */
    case accessDenied = 3

    /**
     A metric value could not be decoded from binary data
     */
    case failedToDecode = 4

    /**
     The requested metric was not found
     */
    case unknownMetric = 5

    /**
     The log file on the server could not be opened.
     */
    case failedToOpenLogFile = 6
}
