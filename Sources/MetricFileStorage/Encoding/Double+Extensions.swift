import Foundation

extension Double {

    static var encodedLength: Int { MemoryLayout<UInt64>.size }

    func toData() -> Data {
        var target = bitPattern.bigEndian
        return withUnsafeBytes(of: &target) {
            Data($0)
        }
    }

    init?(fromData data: Data) {
        guard data.count == MemoryLayout<UInt64>.size else {
            return nil
        }
        let unsigned = Data(data).withUnsafeBytes {
            $0.baseAddress!.load(as: UInt64.self)
        }
        let value = UInt64(bigEndian: unsigned)
        self.init(bitPattern: value)
    }
}
