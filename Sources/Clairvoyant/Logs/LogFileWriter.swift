import Foundation

private typealias TimestampedEncodedData = (date: Date, data: Data)

actor LogFileWriter {
    
    static let maximumFileSizeInBytes = 10_000_000
    
    private static let byteCountLength = 2
    
    var byteCountLength: Int {
        LogFileWriter.byteCountLength
    }
    
    let metricId: MetricId
    
    let metricIdHash: MetricIdHash

    /// The reference to the metric for error logging.
    private weak var metric: AbstractMetric?
    
    private let encoder: BinaryEncoder
    
    private let decoder: BinaryDecoder
    
    private let folder: URL
    
    private let lastValueUrl: URL
    
    private var handle: FileHandle?
    
    private var numberOfBytesInCurrentFile = 0
    
    private var needsNewLogFile = false
    
    /// The internal file manager used to access files
    let fileManager: FileManager = .default
    
    init(id: MetricId, hash: MetricIdHash, folder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder) {
        let metricFolder = folder.appendingPathComponent(hash)
        self.metricId = id
        self.metricIdHash = hash
        self.folder = metricFolder
        self.lastValueUrl = metricFolder.appendingPathComponent("last")
        self.encoder = encoder
        self.decoder = decoder
    }
    
    deinit {
        try? handle?.close()
    }

    /**
     Set the reference to the metric for error handling.
     */
    func set(metric: AbstractMetric) {
        self.metric = metric
    }
    
    private func logError(_ message: String) {
        guard let metric else {
            print("[\(metricId)] \(message)")
            return
        }
        Task {
            await metric.log(message)
        }
    }
    
    // MARK: URLs
    
    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
    
    private func ensureExistenceOfLogFolder() -> Bool {
        guard !exists(folder) else {
            return true
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create log folder: \(error)")
            return false
        }
        return true
    }
    
    private func deleteLastValueFile() {
        try? fileManager.removeItem(at: lastValueUrl)
    }
    
    private func url(for date: Date) -> URL {
        folder.appendingPathComponent("\(Int(date.timeIntervalSince1970))")
    }
    
    /**
     Get the file handle to write a value.
     - Parameter date: The date of the value, if a new log file must be created
     - Throws: `failedToOpenLogFile`
     */
    private func getFileHandle(date: Date) throws -> FileHandle {
        if let handle {
            return handle
        }
        guard !needsNewLogFile else {
            return try createAndOpenFile(with: date)
        }
        guard let url = findLatestFile() else {
            return try createAndOpenFile(with: date)
        }
        // Open new file if old one is too large
        guard fileSize(at: url) < LogFileWriter.maximumFileSizeInBytes else {
            return try createAndOpenFile(with: date)
        }
        do {
            let handle = try FileHandle(forUpdating: url)
            let offset = try handle.seekToEnd()
            self.handle = handle
            self.numberOfBytesInCurrentFile = Int(offset)
            return handle
        } catch {
            logError("File \(url.lastPathComponent): Failed to open: \(error)")
            throw MetricError.failedToOpenLogFile
        }
    }
    
    private func fileSize(at url: URL) -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return Int(attributes[.size] as? UInt64 ?? 0)
        } catch {
            logError("File \(url.lastPathComponent): Failed to read size: \(error)")
            return 0
        }
    }
    
    private func getAllLogFilesWithDates() -> [(url: URL, date: Date)] {
        guard exists(folder) else {
            return []
        }
        do {
            return try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .compactMap {
                    guard let dateString = Int($0.lastPathComponent) else {
                        return nil
                    }
                    return ($0, Date(timeIntervalSince1970: TimeInterval(dateString)))
                }
                .sorted { $0.date < $1.date }
        } catch {
            logError("Failed to get list of files: \(error)")
            return []
        }
    }
    
    private func getAllLogFilesWithIntervals() -> [(url: URL, range: ClosedRange<Date>)] {
        let all = getAllLogFilesWithDates()
        return all.indices.map { i in
            let (url, start) = all[i]
            let end = (i + 1 < all.count) ? all[i+1].date : Date()
            return (url, start...end)
        }
    }

    private func getAllLogFiles() -> [URL] {
        guard exists(folder) else {
            return []
        }
        do {
            return try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { Int($0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            logError("Failed to get list of files: \(error)")
            return []
        }
    }

    
    private func findLatestFile() -> URL? {
        getAllLogFilesWithDates().last?.url
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func createAndOpenFile(with date: Date) throws -> FileHandle {
        let url = url(for: date)
        do {
            try Data().write(to: url)
            let handle = try FileHandle(forUpdating: url)
            self.handle = handle
            needsNewLogFile = false
            numberOfBytesInCurrentFile = 0
            return handle
        } catch {
            logError("Failed to create file \(url.lastPathComponent): \(error)")
            throw MetricError.failedToOpenLogFile
        }
    }
    
    private func closeFile() {
        do {
            try handle?.close()
        } catch {
            logError("Failed to close file: \(error)")
        }
        handle = nil
        numberOfBytesInCurrentFile = 0
    }
    
    // MARK: Writing
    
    func decode<T>(_ data: TimestampedValueData, type: T.Type = T.self) throws -> T where T: Decodable {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    /**
     - Throws:`failedToEncode`
     */
    func encode<T>(_ value: Timestamped<T>) throws -> TimestampedValueData where T: Encodable {
        let valueData: Data
        do {
            valueData = try encoder.encode(value.value)
        } catch {
            logError("Failed to encode value: \(error)")
            throw MetricError.failedToEncode
        }

        let timestampedData: Data
        do {
            timestampedData = try encoder.encode(value.timestamp.timeIntervalSince1970)
        } catch {
            logError("Failed to encode timestamp: \(error)")
            throw MetricError.failedToEncode
        }
        return timestampedData + valueData
    }

    /**
     - Throws: `failedToOpenLogFile`, `failedToEncode`
     */
    func write<T>(_ value: Timestamped<T>) throws -> TimestampedValueData where T: Encodable {
        guard ensureExistenceOfLogFolder() else {
            throw MetricError.failedToOpenLogFile
        }

        let encodedData = try encode(value)
        writeLastValue(encodedData)

        let byteCountData = UInt16(encodedData.count).toData()
        try writeToLog(data: byteCountData + encodedData, date: value.timestamp)
        return encodedData
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func writeToLog(data: Data, date: Date) throws {
        let handle = try getFileHandle(date: date)
        
        do {
            try handle.write(contentsOf: data)
            numberOfBytesInCurrentFile += data.count
        } catch {
            logError("Failed to write data: \(error)")
            throw MetricError.failedToOpenLogFile
        }
        if numberOfBytesInCurrentFile >= LogFileWriter.maximumFileSizeInBytes {
            closeFile()
            needsNewLogFile = true
        }
    }
    
    private func writeLastValue(_ data: TimestampedValueData) {
        do {
            try data.write(to: lastValueUrl)
        } catch {
            logError("Failed to save last value: \(error)")
        }
    }
    
    // MARK: Reading
    
    func encode<T>(_ value: T) throws -> Data where T: Encodable {
        try encoder.encode(value)
    }
    
    func lastValueData() -> TimestampedValueData? {
        guard exists(lastValueUrl) else {
            // TODO: Read last value from history file?
            return nil
        }
        
        do {
            return try .init(contentsOf: lastValueUrl)
        } catch {
            logError("Failed to read last value: \(error)")
            return nil
        }
    }
    
    func lastValue<T>() -> Timestamped<T>? where T: Decodable {
        guard let data = lastValueData() else {
            return nil
        }
        
        do {
            return try .decode(from: data, using: decoder)
        } catch {
            logError("Failed to decode last value: \(error)")
            deleteLastValueFile()
            return nil
        }
    }
    
    // MARK: History
    
    func getHistory<T>(in range: ClosedRange<Date>, maximumValueCount: Int? = nil) -> [Timestamped<T>] where T: Decodable {
        var remainingValuesToRead = maximumValueCount ?? .max
        var result: [Timestamped<T>] = []
        let files = getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }
        for file in files {
            let elements = decode(T.self, from: file.url)
                .filter { range.contains($0.timestamp) }
                .prefix(remainingValuesToRead)
            result.append(contentsOf: elements)
            remainingValuesToRead -= elements.count
            if remainingValuesToRead <= 0 {
                return result
            }
        }
        return result
    }

    func getFullHistory<T>(maximumValueCount: Int? = nil) -> [Timestamped<T>] where T: Decodable {
       getAllLogFiles().map { decode(T.self, from: $0) }.joined().map { $0 }
    }
    
    func getHistoryData(startingFrom start: Date, upTo end: Date, maximumValueCount: Int? = nil) -> Data {
        let result = getHistoryData(startingFrom: start, upTo: end, maximumValueCount: maximumValueCount)
            .map { $0.data }
            .joined()
        return Data(result)
    }
    
    private func getHistoryData(startingFrom start: Date, upTo end: Date, maximumValueCount: Int? = nil) -> [TimestampedEncodedData] {
        let count = maximumValueCount ?? .max
        guard count > 0 else {
            return []
        }
        if start > end {
            return getHistoryDataReversed(in: end...start, count: count)
        }
        return getHistoryData(in: start...end, count: count)
    }
    
    private func getHistoryData(in range: ClosedRange<Date>, count: Int) -> [TimestampedEncodedData] {
        var remainingValuesToRead = count
        var result: [TimestampedEncodedData] = []
        let files = getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }
        for file in files {
            let elements = getElements(from: file.url)
                .filter { range.contains($0.date) }
                .prefix(remainingValuesToRead)
            result.append(contentsOf: elements)
            remainingValuesToRead -= elements.count
            if remainingValuesToRead <= 0 {
                return result
            }
        }
        return result
    }
    
    private func getHistoryDataReversed(in range: ClosedRange<Date>, count: Int) -> [TimestampedEncodedData] {
        var remainingValuesToRead = count
        var result: [TimestampedEncodedData] = []
        let files = getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }.reversed()
        for file in files {
            let elements = getElements(from: file.url)
                .filter { range.contains($0.date) }
                .suffix(remainingValuesToRead)
                .reversed()
            result.append(contentsOf: elements)
            remainingValuesToRead -= elements.count
            if remainingValuesToRead <= 0 {
                return result
            }
        }
        return result
    }
    
    private func decode<T>(_ type: T.Type = T.self, from url: URL) -> [Timestamped<T>] where T: Decodable {
        guard exists(url) else {
            logError("File \(url.lastPathComponent): Not found")
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logError("File \(url.lastPathComponent): Failed to read: \(error)")
            return []
        }
        do {
            let skippedBytes = byteCountLength + decoder.encodedTimestampLength
            return try extractElements(from: data, file: url.lastPathComponent)
                .map {
                    let value = try decoder.decode(T.self, from: $0.data.advanced(by: skippedBytes))
                    return .init(timestamp: $0.date, value: value)
                }
        } catch {
            logError("File \(url.lastPathComponent): Failed to decode: \(error)")
            return []
        }
    }
    
    private func getElements(from url: URL) -> [TimestampedEncodedData] {
        guard exists(url) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logError("File \(url.lastPathComponent): Failed to read: \(error)")
            return []
        }
        return extractElements(from: data, file: url.lastPathComponent)
    }
    
    private func extractElements(from data: Data, file: String) -> [TimestampedEncodedData] {
        var result: [TimestampedEncodedData] = []
        var currentIndex = data.startIndex
        while currentIndex < data.endIndex {
            let startIndexOfTimestamp = currentIndex + byteCountLength
            guard startIndexOfTimestamp <= data.endIndex else {
                logError("File \(file): Only \(data.endIndex - currentIndex) bytes, needed \(byteCountLength) for byte count")
                break
            }
            guard let byteCount = UInt16(fromData: data[currentIndex..<startIndexOfTimestamp]) else {
                logError("File \(file): Invalid byte count")
                break
            }
            let nextIndex = startIndexOfTimestamp + Int(byteCount)
            guard nextIndex <= data.endIndex else {
                logError("File \(file): Needed \(byteCountLength + Int(byteCount)) for timestamped value, has \(data.endIndex - startIndexOfTimestamp)")
                break
            }
            guard byteCount >= decoder.encodedTimestampLength else {
                logError("File \(file): Only \(byteCount) bytes, needed \(decoder.encodedTimestampLength) timestamp")
                break
            }
            let timestampData = data[startIndexOfTimestamp..<startIndexOfTimestamp+decoder.encodedTimestampLength]
            let timestamp: TimeInterval
            do {
                timestamp = try decoder.decode(Double.self, from: timestampData)
            } catch {
                logError("File \(file): Failed to decode timestamp from \(timestampData): \(error)")
                break
            }
            let date = Date(timeIntervalSince1970: timestamp)
            let elementData = data[currentIndex..<nextIndex]
            result.append((date, elementData))
            currentIndex = nextIndex
        }
        return result
    }
}
