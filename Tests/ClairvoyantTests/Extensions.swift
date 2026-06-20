import Foundation

extension URL {

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func remove() throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func removeIfPresent() throws {
        guard exists else {
            return
        }
        try remove()
    }
}
