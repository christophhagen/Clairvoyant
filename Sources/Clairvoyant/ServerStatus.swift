import Foundation

public enum ServerStatus: UInt8, Codable {

    /**
     The server did not respond to a status request

     This case is not set by the server itself, but represents a state of a server status query from outside */
    case noResponse = 0

    /**
     The server is starting up.
     */
    case initializing = 1

    /**
     The server failed to start up.
     */
    case initializationFailure = 2

    /**
     The server is running, but not all functionality is available.
     */
    case reducedFunctionality = 3

    /**
     The server is running, but under heavy load with potentially reduced responsiveness
     */
    case heavyLoad = 4

    /**
     The server is running nominally.
     */
    case nominal = 5

    /**
     The server was terminated due to an internal event.
     */
    case terminated = 6

    /**
     The server never reported any status, e.g. if it doesn't support the functionality.
     */
    case neverReported = 7
}

extension ServerStatus: CustomStringConvertible {

    public var description: String {
        switch self {
        case .noResponse:
            return "Not Responding"
        case .initializing:
            return "Initializing"
        case .initializationFailure:
            return "Initialization Failure"
        case .reducedFunctionality:
            return "Reduced Functionality"
        case .heavyLoad:
            return "Heavy Load"
        case .nominal:
            return "Nominal"
        case .terminated:
            return "Terminated"
        case .neverReported:
            return "Never reported"
        }
    }
}

extension ServerStatus: Timestampable { }

extension ServerStatus: MetricValue {
    
    public static let valueType: MetricType = .serverStatus
}
