import Foundation
import Clairvoyant

protocol FileStorageProtocol {
    
    /// The url where the list of available metrics is stored
    var metricListUrl: URL { get }
}

extension FileStorageProtocol {

    static func folder(for metric: MetricId, in baseFolder: URL) -> URL {
        baseFolder
            .appendingPathComponent(metric.group)
            .appendingPathComponent(metric.id)
    }

    nonisolated func loadMetricListFromDisk() throws -> [MetricInfo] {
        let url = metricListUrl
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(from: data)
    }

    /**
     Save the info of all currently registered metrics to disk, in a human-readable format.

     - Returns: `true`, if the file was written.
     */
    @discardableResult
    func writeMetricsToDisk(_ metrics: [MetricInfo]) throws -> Bool {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(metrics)
            try data.write(to: metricListUrl)
            return true
        } catch {
            print("Failed to save metric list: \(error)")
            return false
        }
    }
}
