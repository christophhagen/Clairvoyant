import Foundation

extension UInt32 {

    func toData() -> Data {
        Data([UInt8(self >> 24 & 0xFF), UInt8(self >> 16 & 0xFF), UInt8(self >> 8 & 0xFF), UInt8(self & 0xFF)])
    }

    init?<T: DataProtocol>(fromData data: T) {
        guard data.count == 4 else {
            return nil
        }
        let bytes = Array(data)
        self = UInt32(bytes[0]) << 24 | UInt32(bytes[0]) << 16 | UInt32(bytes[0]) << 8 | UInt32(bytes[0])
    }
}
