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
     A metric value could not be decoded from binary data
     */
    case failedToDecode = 3

    /**
     The log file on the server could not be opened.
     */
    case failedToOpenLogFile = 4

    /**
     The standard 404 response.
     */
    case notFound = 5

    /**
     The metric type does not fit the intended Swift type.
     */
    case typeMismatch = 6

    /**
     A log file could not be deleted while deleting metric history.
     */
    case failedToDeleteLogFile = 7

}

extension MetricError {

    public init?(statusCode: Int) {
        switch statusCode {
        case 424: self = .failedToEncode // 1, .failedDependency
        case 422: self = .logFileCorrupted // 2, .unprocessableEntity
        case 417: self = .failedToDecode // 4, .expectationFailed
        case 423: self = .failedToOpenLogFile // 6, .locked
        case 404: self = .notFound // 8, .notFound
        case 428: self = .typeMismatch // 12, .preconditionRequired
        case 304: self = .failedToDeleteLogFile // 14, .notModified
        default:
            return nil
        }
    }
}

