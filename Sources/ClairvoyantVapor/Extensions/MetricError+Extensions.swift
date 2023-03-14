import Foundation
import Vapor
import Clairvoyant

extension MetricError {
    var status: HTTPResponseStatus {
        switch self {
        case .failedToEncode: return .failedDependency // 424
        case .logFileCorrupted: return .unprocessableEntity // 422
        case .accessDenied: return .unauthorized // 401
        case .badMetricId: return .preconditionFailed // 412
        case .failedToDecode: return .expectationFailed // 417
        case .failedToOpenLogFile: return .locked // 423
        case .requestFailed: return .serviceUnavailable // 503
        case .notFound: return .notFound // 404
        case .badGateway: return .badGateway // 502
        case .internalError: return .internalServerError // 500
        case .noValueAvailable: return .gone // 410
        case .typeMismatch: return .preconditionRequired // 428
        case .noObserver: return .misdirectedRequest // 503
        }
    }
}
