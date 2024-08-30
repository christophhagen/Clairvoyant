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
        guard url.exists else {
            return []
        }
        let data = try rethrow(.readFile, "Metric list") {
            try Data(contentsOf: url)
        }
        return try rethrow(.decodeFile, "Metric list") {
            try JSONDecoder().decode(from: data)
        }
    }

    /**
     Save the info of all currently registered metrics to disk, in a human-readable format.

     - Returns: `true`, if the file was written.
     */
    func writeMetricsToDisk(_ metrics: [MetricInfo]) throws {

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try rethrow(.encodeFile, "Metric list") {
            try encoder.encode(metrics)
        }
        try rethrow(.writeFile, "Metric list") {
            try data.write(to: metricListUrl)
        }
    }
}
