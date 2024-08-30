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

    var attributes: [FileAttributeKey : Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError {
            print("FileAttribute error: \(error)")
        }
        return nil
    }

    var fileSize: Int {
        return Int(attributes?[.size] as? UInt64 ?? 0)
    }

    var fileSizeString: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var creationDate: Date? {
        return attributes?[.creationDate] as? Date
    }

    var allocatedFileSize: Int? {
        do {
            let val = try self.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return val.totalFileAllocatedSize ?? val.fileAllocatedSize
        } catch {
            print(error)
            return nil
        }
    }
}
