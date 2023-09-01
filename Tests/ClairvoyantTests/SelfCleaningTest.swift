import Foundation
import XCTest
import Clairvoyant

class SelfCleaningTest: XCTestCase {

    var temporaryDirectory: URL {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, *) {
            return URL.temporaryDirectory
        } else {
            // Fallback on earlier versions
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }
    
    var logFolder: URL {
        temporaryDirectory.appendingPathComponent("logs")
    }
    
    override func setUp() async throws {
        try removeAllFiles()
    }
    
    override func tearDown() async throws {
        try removeAllFiles()
    }
    
    private func removeAllFiles() throws {
        let url = logFolder
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        MetricObserver.standard = nil
    }
}
