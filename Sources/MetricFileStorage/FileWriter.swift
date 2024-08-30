import Foundation
import Clairvoyant

private typealias TimestampedValueData = Data
private typealias TimestampedEncodedData = (date: Date, data: Data)

final class FileWriter<T> where T: MetricValue {

    var maximumFileSizeInBytes: Int

    private let byteCountLength = 2

    private let timestampLength = Double.encodedLength

    /// The number of bytes to skip for the header (containing number of bytes and timestamp)
    private let headerByteCount = 2 + Double.encodedLength

    let metricId: MetricId

    private let encoder: AnyBinaryEncoder

    private let decoder: AnyBinaryDecoder

    private let folder: URL

    private let lastValueUrl: URL

    private var handle: FileHandle?

    private var numberOfBytesInCurrentFile = 0

    private var needsNewLogFile = false

    /// The internal file manager used to access files
    let fileManager: FileManager = .default

    init(id: MetricId, folder: URL, encoder: AnyBinaryEncoder, decoder: AnyBinaryDecoder, fileSize: Int) {
        let metricFolder = MultiFileStorageAsync.folder(for: id, in: folder)
        self.metricId = id
        self.folder = metricFolder
        self.lastValueUrl = metricFolder.appendingPathComponent(MultiFileStorageAsync.lastValueFileName)
        self.encoder = encoder
        self.decoder = decoder
        self.maximumFileSizeInBytes = fileSize
    }

    deinit {
        try? handle?.close()
    }

    // MARK: URLs

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func ensureExistenceOfLogFolder() throws {
        if exists(folder) {
            return
        }
        try rethrow(.createFolder, "Log folder") {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func deleteLastValueFile() throws {
        try rethrow(.deleteFile, "Last value file") {
            try fileManager.removeItem(at: lastValueUrl)
        }
    }

    private func url(for date: Date) -> URL {
        folder.appendingPathComponent("\(Int(date.timeIntervalSince1970 * 1000))")
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
        guard let url = try findLatestFile() else {
            return try createAndOpenFile(with: date)
        }
        // Open new file if old one is too large
        guard try fileSize(at: url) < maximumFileSizeInBytes else {
            return try createAndOpenFile(with: date)
        }
        return try rethrow(.openFile, url.lastPathComponent) {
            let handle = try FileHandle(forUpdating: url)
            let offset = try handle.seekToEnd()
            self.handle = handle
            self.numberOfBytesInCurrentFile = Int(offset)
            return handle
        }
    }

    private func fileSize(at url: URL) throws -> Int {
        try rethrow(.fileAttributes, url.lastPathComponent) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return Int(attributes[.size] as? UInt64 ?? 0)
        }
    }

    private func getAllLogFilesWithStartDates() throws -> [(url: URL, date: Date)] {
        guard exists(folder) else {
            return []
        }
        return try rethrow(.readFolder, folder.lastPathComponent) {
            try folder.contents()
        }
        .compactMap {
            guard let dateString = Int($0.lastPathComponent) else {
                return nil
            }
            return (url: $0, date: Date(timeIntervalSince1970: TimeInterval(dateString) / 1000))
        }
        .sorted { $0.date }
    }

    /**
     A sorted list of files with the date intervals of the data contained in them
     */
    private func getAllLogFilesWithIntervals() throws -> [(url: URL, range: ClosedRange<Date>)] {
        let all = try getAllLogFilesWithStartDates()
        return all.indices.map { i in
            let (url, start) = all[i]
            let end = (i + 1 < all.count) ? all[i+1].date : .distantFuture
            return (url, start...end)
        }
    }

    private func getAllLogFiles() throws -> [URL] {
        guard exists(folder) else {
            return []
        }
            return try rethrow(.readFolder, folder.lastPathComponent) {
                try folder.contents()
            }
            .filter { Int($0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }


    private func findLatestFile() throws -> URL? {
        try getAllLogFilesWithStartDates().last?.url
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func createAndOpenFile(with date: Date) throws -> FileHandle {
        let url = url(for: date)
        try rethrow(.writeFile, url.lastPathComponent) {
            try Data().write(to: url)
        }
        let handle = try rethrow(.openFile, url.lastPathComponent) {
            try FileHandle(forUpdating: url)
        }
        self.handle = handle
        needsNewLogFile = false
        numberOfBytesInCurrentFile = 0
        return handle
    }

    private func closeFile() {
        try? handle?.close()
        handle = nil
        numberOfBytesInCurrentFile = 0
    }

    // MARK: Writing

    private func encode<E>(_ value: E) throws -> Data where E: Encodable {
        try rethrow(.encodeData, "\(value)") {
            try encoder.encode(value)
        }
    }

    private func encode(_ values: [Timestamped<T>]) throws -> Data {
        try rethrow(.encodeData, "\(values.count) \(type(of: values))") {
            try encoder.encode(values)
        }
    }

    /**
     - Throws:`failedToEncode`
     */
    private func encodeDataForStream(_ value: Timestamped<T>) throws -> TimestampedValueData {
        let valueData = try encode(value.value)
        let timestampedData = value.timestamp.timeIntervalSince1970.toData()
        let count = timestampedData.count + valueData.count
        return UInt16(count).toData() + timestampedData + valueData
    }

    /**
     - Throws: `failedToOpenLogFile`, `failedToEncode`
     */
    func write(_ value: Timestamped<T>) throws {
        try ensureExistenceOfLogFolder()
        try write(lastValue: value)
        let streamEncodedData = try encodeDataForStream(value)
        try writeToLog(data: streamEncodedData, date: value.timestamp)
    }

    func writeOnlyToLog(_ value: Timestamped<T>) throws {
        try ensureExistenceOfLogFolder()
        let streamEncodedData = try encodeDataForStream(value)
        try writeToLog(data: streamEncodedData, date: value.timestamp)
    }

    /**
     - Throws: `failedToOpenLogFile`
     */
    private func writeToLog(data: Data, date: Date) throws {
        let handle = try getFileHandle(date: date)

        try rethrow(.writeFile, "File for \(date.formatted())") {
            try handle.write(contentsOf: data)
        }
        numberOfBytesInCurrentFile += data.count

        if numberOfBytesInCurrentFile >= maximumFileSizeInBytes {
            closeFile()
            needsNewLogFile = true
        }
    }

    func write(lastValue: Timestamped<T>) throws {
        let data = try encode(lastValue)
        try writeLastValue(data)
    }

    private func writeLastValue(_ data: Data) throws {
        try rethrow(.writeFile, "Last value") {
            try data.write(to: lastValueUrl)
        }
    }

    // MARK: Reading

    private func lastValueData() throws -> TimestampedValueData? {
        guard exists(lastValueUrl) else {
            // TODO: Read last value from history file?
            return nil
        }

        return try rethrow(.readFile, "Last value") {
            return try .init(contentsOf: lastValueUrl)
        }
    }

    func lastValue() throws -> Timestamped<T>? {
        guard let data = try lastValueData() else {
            return nil
        }
        return try rethrow(.decodeData, "Last value") {
            try decoder.decode(Timestamped<T>.self, from: data)
        } onError: {
            try? deleteLastValueFile()
        }
    }

    // MARK: History

    func numberOfDataPoints() throws -> Int {
        try getAllLogFiles().reduce(0) {
            try $0 + countValues(in: $1)
        }
    }

    private func countValues(in file: URL) throws -> Int {
        let data = try Data(contentsOf: file)

        let filename = file.lastPathComponent
        var count = 0
        var currentIndex = data.startIndex
        while currentIndex < data.endIndex {
            let (_, nextIndex) = try decodeElement(data: data, file: filename, currentIndex: &currentIndex)
            count += 1
            currentIndex = nextIndex
        }
        return count
    }

    func getHistory(from start: Date, to end: Date, maximumValueCount: Int? = nil) throws -> [Timestamped<T>] {
        let count = maximumValueCount ?? .max
        guard count > 0 else {
            return []
        }
        if start <= end {
            return try getHistory(in: start...end, count: count)
        } else {
            return try getHistoryReversed(in: end...start, count: count)
        }
    }

    private func getHistory(in range: ClosedRange<Date>, count: Int) throws -> [Timestamped<T>] {
        var remainingValuesToRead = count
        var result: [Timestamped<T>] = []
        let files = try getAllLogFilesWithIntervals()
            .filter { $0.range.overlaps(range) }
        for file in files {
            let elements = try decodeTimestampedStream(from: file.url)
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

    private func getHistoryReversed(in range: ClosedRange<Date>, count: Int) throws -> [Timestamped<T>] {
        var remainingValuesToRead = count
        var result: [Timestamped<T>] = []
        let files = try getAllLogFilesWithIntervals()
            .filter { $0.range.overlaps(range) }
            .reversed()
        for file in files {
            // Opportunistically get history data, ignore file errors
            let elements = try decodeTimestampedStream(from: file.url)
                .filter { range.contains($0.timestamp) }
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

    func getFullHistory(maximumValueCount: Int? = nil) throws -> [Timestamped<T>] {
        try getAllLogFiles()
            .map { try decodeTimestampedStream(from: $0) }.joined().map { $0 }
    }

    private func decodeTimestampedStream(from url: URL) throws -> [Timestamped<T>] {
        guard exists(url) else {
            throw FileStorageError(.missingFile, url.lastPathComponent)
        }
        let data = try rethrow(.readFile, url.lastPathComponent) {
            try Data(contentsOf: url)
        }
        return try extractElements(from: data, file: url.lastPathComponent)
            .map {
                let valueData = $0.data.advanced(by: headerByteCount)
                let value: T = try rethrow(.decodeFile, url.lastPathComponent) {
                    try decoder.decode(from: valueData)
                }
                return .init(value: value, timestamp: $0.date)
            }
    }

    private func getElements(from url: URL) throws -> [TimestampedEncodedData] {
        guard exists(url) else {
            return []
        }
        let data = try rethrow(.readFile, url.lastPathComponent) {
            try Data(contentsOf: url)
        }
        return try extractElements(from: data, file: url.lastPathComponent)
    }

    private func extractElements(from data: Data, file: String) throws -> [TimestampedEncodedData] {
        var result: [TimestampedEncodedData] = []
        var currentIndex = data.startIndex
        while currentIndex < data.endIndex {
            let (startIndexOfTimestamp, nextIndex) = try decodeElement(data: data, file: file, currentIndex: &currentIndex)
            let timestampData = data[startIndexOfTimestamp..<startIndexOfTimestamp+timestampLength]
            let timestamp = Double(fromData: timestampData)!
            let date = Date(timeIntervalSince1970: timestamp)
            let elementData = data[currentIndex..<nextIndex]
            result.append((date, elementData))
            currentIndex = nextIndex
        }
        return result
    }

    private func decodeElement(data: Data, file: String, currentIndex: inout Int) throws -> (start: Int, next: Int) {
        let startIndexOfTimestamp = currentIndex + byteCountLength
        guard startIndexOfTimestamp <= data.endIndex else {
            throw FileStorageError(.decodeFile, "File \(file): Byte count - \(data.endIndex - currentIndex) of \(byteCountLength) bytes")
        }
        guard let byteCount = UInt16(fromData: data[currentIndex..<startIndexOfTimestamp]) else {
            throw FileStorageError(.decodeFile, "File \(file): Byte count - Invalid")
        }
        let nextIndex = startIndexOfTimestamp + Int(byteCount)
        guard nextIndex <= data.endIndex else {
            throw FileStorageError(.decodeFile, "File \(file): Element - \(data.endIndex - startIndexOfTimestamp) of \(byteCountLength + Int(byteCount)) bytes")
        }
        guard byteCount >= timestampLength else {
            throw FileStorageError(.decodeFile, "File \(file): Timestamp - \(byteCount) of \(timestampLength) bytes")
        }
        return (startIndexOfTimestamp, nextIndex)
    }

    // MARK: Deleting history

    private func deleteFile(at url: URL) throws {
        try rethrow(.deleteFile, url.lastPathComponent) {
            try url.removeIfPresent()
        }
    }

    func deleteHistory(from start: Date, to end: Date) throws {
        // Prevent messing with open file
        closeFile()

        // Only select files containing items before the date
        let files = try getAllLogFilesWithIntervals()

        for (url, range) in files {
            guard range.lowerBound <= end && range.upperBound >= start else {
                continue
            }
            if range.lowerBound >= start && range.upperBound <= end {
                // File completely contained in interval to delete
                try deleteFile(at: url)
                // If an error is thrown here, then only the oldest history will be deleted,
                // so at least no inconsistency
            } else {
                // Delete some entries within file
                try deleteElementsInFile(at: url, from: start, to: end)
            }
        }
    }

    private func deleteElementsInFile(at url: URL, from start: Date, to end: Date) throws {
        let remainingElements = try getElements(from: url)
            .filter { $0.date < start || $0.date > end }
        guard let start = remainingElements.first?.date else {
            // No elements to keep, delete old file
            print("Nothing to keep")
            try deleteFile(at: url)
            return
        }
        let data = Data(remainingElements.map { $0.data }.joined())

        // Create new file with different date
        let newFileUrl = self.url(for: start)
        try rethrow(.writeFile, newFileUrl.lastPathComponent) {
            try data.write(to: newFileUrl)
        }

        if newFileUrl.lastPathComponent == url.lastPathComponent {
            // Writing to same file due to same timestamp
            return
        }

        // Delete old file
        try rethrow(.deleteFile, url.lastPathComponent) {
            try deleteFile(at: url)
        } onError: {
            // Attempt to restore consistency by deleting new file
            try? deleteFile(at: newFileUrl)
        }
    }

    // MARK: Size

    var usedDiskSpace: Int {
        folder.fileSize
    }
}
