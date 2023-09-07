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
     The requested metric was not found, or a duplicate id was used
     */
    case badMetricId = 5

    /**
     The log file on the server could not be opened.
     */
    case failedToOpenLogFile = 6

    /**
     A request to a metric instance failed
     */
    case requestFailed = 7

    /**
     The standard 404 response.
     */
    case notFound = 8

    /**
     Proxy error
     */
    case badGateway = 9

    /**
     Some internal error occured.
     */
    case internalError = 10

    /**
     The metric does not yet provide a value.
     */
    case noValueAvailable = 11

    /**
     The metric type does not fit the intended Swift type.
     */
    case typeMismatch = 12

    /**
     There is no metric observer available to perform the function.
     */
    case noObserver = 13

    /**
     A log file could not be deleted while deleting metric history.
     */
    case failedToDeleteLogFile = 14

}

extension MetricError {

    public init?(statusCode: Int) {
        switch statusCode {
        case 424: self = .failedToEncode // 1, .failedDependency
        case 422: self = .logFileCorrupted // 2, .unprocessableEntity
        case 401: self = .accessDenied // 3, .unauthorized
        case 417: self = .failedToDecode // 4, .expectationFailed
        case 412: self = .badMetricId // 5, .preconditionFailed
        case 423: self = .failedToOpenLogFile // 6, .locked
        case 503: self = .requestFailed // 7, .serviceUnavailable
        case 404: self = .notFound // 8, .notFound
        case 502: self = .badGateway // 9, .badGateway
        case 500: self = .internalError // 10, .internalServerError
        case 410: self = .noValueAvailable // 11, .gone
        case 428: self = .typeMismatch // 12, .preconditionRequired
        case 421: self = .noObserver // 13, .misdirectedRequest
        case 304: self = .failedToDeleteLogFile // 14, .notModified
        default:
            return nil
        }
    }
}

