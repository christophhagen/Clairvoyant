import Foundation

extension FileManager {

    private func fileSizeEnumerator(at directory: URL) -> DirectoryEnumerator? {
        enumerator(at: directory,
                   includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                   options: []) { (_, error) -> Bool in
            print(error)
            return false
        }
    }

    func directorySize(_ directory: URL) -> Int {
        return fileSizeEnumerator(at: directory)?
            .compactMap { $0 as? URL }
            .reduce(0) { $0 + $1.fileSize } ?? 0
    }
}
