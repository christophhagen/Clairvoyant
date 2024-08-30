import Foundation

public struct FileStorageError: Error {

    public let operation: Operation

    public let description: String

    public let error: Error?

    public init(_ operation: Operation, _ description: String, error: Error? = nil) {
        self.operation = operation
        self.description = description
        self.error = error
    }
}

extension FileStorageError {

    public enum Operation {

        // Metrics

        case metricId

        case metricType

        // Files

        case encodeFile

        case writeFile

        case readFile

        case decodeFile

        case deleteFile

        case openFile

        case missingFile

        case fileAttributes

        // Folders

        case createFolder

        case readFolder

        case deleteFolder

        // Data

        case encodeData

        case decodeData
    }
}

func rethrow<T>(_ operation: FileStorageError.Operation, _ description: String, _ block: () throws -> T, onError: () -> () = { }) rethrows -> T {
    do {
        return try block()
    } catch {
        onError()
        throw FileStorageError(operation, description, error: error)
    }
}
