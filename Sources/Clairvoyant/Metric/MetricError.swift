import Foundation
import Vapor

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

    case internalError = 10

    case noValueAvailable = 11

}

extension MetricError {

    var status: HTTPResponseStatus {
        switch self {
        case .failedToEncode: return .failedDependency // 424
        case .logFileCorrupted: return .unprocessableEntity // 422
        case .accessDenied: return .unauthorized // 401
        case .failedToDecode: return .expectationFailed // 417
        case .unknownMetric: return .preconditionFailed // 412
        case .failedToOpenLogFile: return .locked // 423
        case .requestFailed: return .serviceUnavailable // 503
        case .notFound: return .notFound // 404
        case .badGateway: return .badGateway // 502
        case .internalError: return .internalServerError // 500
        case .noValueAvailable: return .gone // 410
        }
    }

    init?(statusCode: Int) {
        switch statusCode {
        case 424: self = .failedToEncode
        case 422: self = .logFileCorrupted
        case 401: self = .accessDenied
        case 417: self = .failedToDecode
        case 412: self = .unknownMetric
        case 423: self = .failedToOpenLogFile
        case 503: self = .requestFailed
        case 404: self = .notFound
        case 502: self = .badGateway
        case 500: self = .internalError
        case 410: self = .noValueAvailable
        default:
            return nil
        }
    }
}
