import Foundation

private typealias TimestampedEncodedData = (date: Date, data: Data)

final class LogFileWriter<T> where T: MetricValue {
    
    var maximumFileSizeInBytes: Int

    private let byteCountLength = 2

    private let timestampLength = Double.encodedLength

    /// The number of bytes to skip for the header (containing number of bytes and timestamp)
    private let headerByteCount = 2 + Double.encodedLength
    
    let metricId: MetricId
    
    let metricIdHash: MetricIdHash

    var logClosure: (String) async -> Void
    
    private let encoder: BinaryEncoder
    
    private let decoder: BinaryDecoder
    
    private let folder: URL
    
    private let lastValueUrl: URL
    
    private var handle: FileHandle?
    
    private var numberOfBytesInCurrentFile = 0
    
    private var needsNewLogFile = false
    
    /// The internal file manager used to access files
    let fileManager: FileManager = .default
    
    init(id: MetricId, hash: MetricIdHash, folder: URL, encoder: BinaryEncoder, decoder: BinaryDecoder, fileSize: Int, logClosure: @escaping (String) async -> Void) {
        let metricFolder = folder.appendingPathComponent(hash)
        self.metricId = id
        self.metricIdHash = hash
        self.folder = metricFolder
        self.lastValueUrl = metricFolder.appendingPathComponent("last")
        self.encoder = encoder
        self.decoder = decoder
        self.maximumFileSizeInBytes = fileSize
        self.logClosure = logClosure
    }
    
    deinit {
        try? handle?.close()
    }
    
    private func logError(_ message: String) async {
        await logClosure(message)
    }
    
    // MARK: URLs
    
    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
    
    private func ensureExistenceOfLogFolder() async -> Bool {
        guard !exists(folder) else {
            return true
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            await logError("Failed to create log folder: \(error)")
            return false
        }
        return true
    }
    
    func deleteLastValueFile() async throws {
        do {
            try fileManager.removeItem(at: lastValueUrl)
        } catch {
            await logError("Failed to delete last value file: \(error)")
            throw MetricError.failedToDeleteLogFile
        }
    }
    
    private func url(for date: Date) -> URL {
        folder.appendingPathComponent("\(Int(date.timeIntervalSince1970))")
    }
    
    /**
     Get the file handle to write a value.
     - Parameter date: The date of the value, if a new log file must be created
     - Throws: `failedToOpenLogFile`
     */
    private func getFileHandle(date: Date) async throws -> FileHandle {
        if let handle {
            return handle
        }
        guard !needsNewLogFile else {
            return try await createAndOpenFile(with: date)
        }
        guard let url = await findLatestFile() else {
            return try await createAndOpenFile(with: date)
        }
        // Open new file if old one is too large
        guard await fileSize(at: url) < maximumFileSizeInBytes else {
            return try await createAndOpenFile(with: date)
        }
        do {
            let handle = try FileHandle(forUpdating: url)
            let offset = try handle.seekToEnd()
            self.handle = handle
            self.numberOfBytesInCurrentFile = Int(offset)
            return handle
        } catch {
            await logError("File \(url.lastPathComponent): Failed to open: \(error)")
            throw MetricError.failedToOpenLogFile
        }
    }
    
    private func fileSize(at url: URL) async -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return Int(attributes[.size] as? UInt64 ?? 0)
        } catch {
            await logError("File \(url.lastPathComponent): Failed to read size: \(error)")
            return 0
        }
    }
    
    private func getAllLogFilesWithStartDates() async -> [(url: URL, date: Date)] {
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
            await logError("Failed to get list of files: \(error)")
            return []
        }
    }

    /**
     A sorted list of files with the date intervals of the data contained in them
     */
    private func getAllLogFilesWithIntervals() async -> [(url: URL, range: ClosedRange<Date>)] {
        let all = await getAllLogFilesWithStartDates()
        return all.indices.map { i in
            let (url, start) = all[i]
            let end = (i + 1 < all.count) ? all[i+1].date : Date()
            return (url, start...end)
        }
    }

    private func getAllLogFiles() async -> [URL] {
        guard exists(folder) else {
            return []
        }
        do {
            return try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { Int($0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            await logError("Failed to get list of files: \(error)")
            return []
        }
    }

    
    private func findLatestFile() async -> URL? {
        await getAllLogFilesWithStartDates().last?.url
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func createAndOpenFile(with date: Date) async throws -> FileHandle {
        let url = url(for: date)
        do {
            try Data().write(to: url)
            let handle = try FileHandle(forUpdating: url)
            self.handle = handle
            needsNewLogFile = false
            numberOfBytesInCurrentFile = 0
            return handle
        } catch {
            await logError("Failed to create file \(url.lastPathComponent): \(error)")
            throw MetricError.failedToOpenLogFile
        }
    }
    
    private func closeFile() async {
        do {
            try handle?.close()
        } catch {
            await logError("Failed to close file: \(error)")
        }
        handle = nil
        numberOfBytesInCurrentFile = 0
    }
    
    // MARK: Writing

    func decodeTimestampedValues(from data: Data) throws -> [Timestamped<T>] {
        do {
            return try decoder.decode(from: data)
        } catch {
            throw MetricError.failedToDecode
        }
    }

    func encode(_ value: Timestamped<T>) async throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            await logError("Failed to encode value: \(error)")
            throw MetricError.failedToEncode
        }
    }

    func encode(_ values: [Timestamped<T>]) async throws -> Data {
        do {
            return try encoder.encode(values)
        } catch {
            await logError("Failed to encode values: \(error)")
            throw MetricError.failedToEncode
        }
    }

    /**
     - Throws:`failedToEncode`
     */
    private func encodeDataForStream(_ value: Timestamped<T>) async throws -> TimestampedValueData {
        let valueData: Data
        do {
            valueData = try encoder.encode(value.value)
        } catch {
            await logError("Failed to encode value: \(error)")
            throw MetricError.failedToEncode
        }

        let timestampedData = value.timestamp.timeIntervalSince1970.toData()
        let count = timestampedData.count + valueData.count
        return UInt16(count).toData() + timestampedData + valueData
    }

    /**
     - Throws: `failedToOpenLogFile`, `failedToEncode`
     */
    func write(_ value: Timestamped<T>) async throws {
        guard await ensureExistenceOfLogFolder() else {
            throw MetricError.failedToOpenLogFile
        }

        try await write(lastValue: value)
        let streamEncodedData = try await encodeDataForStream(value)
        try await writeToLog(data: streamEncodedData, date: value.timestamp)
    }

    func writeOnlyToLog(_ value: Timestamped<T>) async throws {
        guard await ensureExistenceOfLogFolder() else {
            throw MetricError.failedToOpenLogFile
        }

        let streamEncodedData = try await encodeDataForStream(value)
        try await writeToLog(data: streamEncodedData, date: value.timestamp)
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func writeToLog(data: Data, date: Date) async throws {
        let handle = try await getFileHandle(date: date)
        
        do {
            try handle.write(contentsOf: data)
            numberOfBytesInCurrentFile += data.count
        } catch {
            await logError("Failed to write data: \(error)")
            throw MetricError.failedToOpenLogFile
        }
        if numberOfBytesInCurrentFile >= maximumFileSizeInBytes {
            await closeFile()
            needsNewLogFile = true
        }
    }

    func write(lastValue: Timestamped<T>) async throws {
        let data = try await encode(lastValue)
        await writeLastValue(data)
    }
    
    private func writeLastValue(_ data: Data) async {
        do {
            try data.write(to: lastValueUrl)
        } catch {
            await logError("Failed to save last value: \(error)")
        }
    }
    
    // MARK: Reading
    
    func lastValueData() async -> TimestampedValueData? {
        guard exists(lastValueUrl) else {
            // TODO: Read last value from history file?
            return nil
        }
        
        do {
            return try .init(contentsOf: lastValueUrl)
        } catch {
            await logError("Failed to read last value: \(error)")
            return nil
        }
    }
    
    func lastValue() async -> Timestamped<T>? {
        guard let data = await lastValueData() else {
            return nil
        }
        
        do {
            return try decoder.decode(Timestamped<T>.self, from: data)
        } catch {
            await logError("Failed to decode last value: \(error)")
            try? await deleteLastValueFile()
            return nil
        }
    }
    
    // MARK: History
    
    func getHistory(in range: ClosedRange<Date>, maximumValueCount: Int? = nil) async -> [Timestamped<T>] {
        var remainingValuesToRead = maximumValueCount ?? .max
        var result: [Timestamped<T>] = []
        let files = await getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }
        for file in files {
            let elements = await decodeTimestampedStream(from: file.url)
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

    func getFullHistory(maximumValueCount: Int? = nil) async -> [Timestamped<T>] {
        await getAllLogFiles().asyncMap { await self.decodeTimestampedStream(from: $0) }.joined().map { $0 }
    }
    
    func getHistoryData(startingFrom start: Date, upTo end: Date, maximumValueCount: Int? = nil) async -> Data {
        let result = await getHistoryData(startingFrom: start, upTo: end, maximumValueCount: maximumValueCount)
            .map { $0.data }
            .joined()
        return Data(result)
    }
    
    private func getHistoryData(startingFrom start: Date, upTo end: Date, maximumValueCount: Int? = nil) async -> [TimestampedEncodedData] {
        let count = maximumValueCount ?? .max
        guard count > 0 else {
            return []
        }
        if start > end {
            return await getHistoryDataReversed(in: end...start, count: count)
        }
        return await getHistoryData(in: start...end, count: count)
    }
    
    private func getHistoryData(in range: ClosedRange<Date>, count: Int) async -> [TimestampedEncodedData] {
        var remainingValuesToRead = count
        var result: [TimestampedEncodedData] = []
        let files = await getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }
        for file in files {
            // Opportunistically get history data, ignore file errors
            let elements = await getReadableElements(from: file.url)
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
    
    private func getHistoryDataReversed(in range: ClosedRange<Date>, count: Int) async -> [TimestampedEncodedData] {
        var remainingValuesToRead = count
        var result: [TimestampedEncodedData] = []
        let files = await getAllLogFilesWithIntervals().filter { $0.range.overlaps(range) }.reversed()
        for file in files {
            // Opportunistically get history data, ignore file errors
            let elements = await getReadableElements(from: file.url)
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
    
    private func decodeTimestampedStream(from url: URL) async -> [Timestamped<T>] {
        guard exists(url) else {
            await logError("File \(url.lastPathComponent): Not found")
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            await logError("File \(url.lastPathComponent): Failed to read: \(error)")
            return []
        }
        do {
            return try await extractElements(from: data, file: url.lastPathComponent)
                .map {
                    let valueData = $0.data.advanced(by: headerByteCount)
                    let value = try decoder.decode(T.self, from: valueData)
                    return .init(value: value, timestamp: $0.date)
                }
        } catch {
            await logError("File \(url.lastPathComponent): Failed to decode: \(error)")
            return []
        }
    }

    private func getReadableElements(from url: URL) async -> [TimestampedEncodedData] {
        (try? await getElements(from: url)) ?? []
    }
    
    private func getElements(from url: URL) async throws -> [TimestampedEncodedData] {
        guard exists(url) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            await logError("File \(url.lastPathComponent): Failed to read: \(error)")
            throw MetricError.failedToOpenLogFile
        }
        return try await extractElements(from: data, file: url.lastPathComponent)
    }
    
    private func extractElements(from data: Data, file: String) async throws -> [TimestampedEncodedData] {
        var result: [TimestampedEncodedData] = []
        var currentIndex = data.startIndex
        while currentIndex < data.endIndex {
            let startIndexOfTimestamp = currentIndex + byteCountLength
            guard startIndexOfTimestamp <= data.endIndex else {
                await logError("File \(file): Only \(data.endIndex - currentIndex) bytes, needed \(byteCountLength) for byte count")
                throw MetricError.logFileCorrupted
            }
            guard let byteCount = UInt16(fromData: data[currentIndex..<startIndexOfTimestamp]) else {
                await logError("File \(file): Invalid byte count")
                throw MetricError.logFileCorrupted
            }
            let nextIndex = startIndexOfTimestamp + Int(byteCount)
            guard nextIndex <= data.endIndex else {
                await logError("File \(file): Needed \(byteCountLength + Int(byteCount)) for timestamped value, has \(data.endIndex - startIndexOfTimestamp)")
                throw MetricError.logFileCorrupted
            }
            guard byteCount >= timestampLength else {
                await logError("File \(file): Only \(byteCount) bytes, needed \(timestampLength) for timestamp")
                throw MetricError.logFileCorrupted
            }
            let timestampData = data[startIndexOfTimestamp..<startIndexOfTimestamp+timestampLength]
            let timestamp = Double(fromData: timestampData)!
            let date = Date(timeIntervalSince1970: timestamp)
            let elementData = data[currentIndex..<nextIndex]
            result.append((date, elementData))
            currentIndex = nextIndex
        }
        return result
    }

    // MARK: Deleting history

    private func deleteFile(at url: URL) async throws {
        guard exists(url) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            await logError("File \(url.lastPathComponent): Failed to delete: \(error)")
            throw MetricError.failedToDeleteLogFile
        }
    }

    func deleteHistory(before date: Date) async throws {
        // Prevent messing with open file
        await closeFile()

        // Only select files containing items before the date
        let files = await getAllLogFilesWithIntervals().prefix { $0.range.upperBound < date }
        for (url, range) in files {
            if date < range.lowerBound {
                // File contains only older entries
                try await deleteFile(at: url)
                // If an error is thrown here, then only the oldest history will be deleted,
                // so at least no inconsistency
            } else {
                // Delete some entries within file
                try await deleteElementsInFile(at: url, before: date)
            }
        }
    }

    private func deleteElementsInFile(at url: URL, before date: Date) async throws {
        let remainingElements = try await getElements(from: url)
            .drop { $0.date < date }
        guard let start = remainingElements.first?.date else {
            // No elements to keep, delete old file
            try await deleteFile(at: url)
            return
        }
        let data = Data(remainingElements.map { $0.data }
            .joined())

        // Create new file with different date
        let newFileUrl = self.url(for: start)
        do {
            try data.write(to: newFileUrl)
        } catch {
            await logError("File \(newFileUrl.lastPathComponent): Failed to create updated history file: \(error)")
            throw MetricError.failedToOpenLogFile
        }

        // Delete old file
        do {
            try await deleteFile(at: url)
        } catch {
            // Attempt to restore consistency by deleting new file
            try? await deleteFile(at: newFileUrl)
            throw error
        }
    }
}
