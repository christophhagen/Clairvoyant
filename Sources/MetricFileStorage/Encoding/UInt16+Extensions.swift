import Foundation

extension UInt16 {

    func toData() -> Data {
        Data([UInt8(self >> 8 & 0xFF), UInt8(self & 0xFF)])
    }

    init?<T: DataProtocol>(fromData data: T) {
        guard data.count == 2 else {
            return nil
        }
        let bytes = Array(data)
        self = UInt16(UInt32(bytes[0]) << 8 | UInt32(bytes[1]))
    }
}
