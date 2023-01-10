import Foundation

#if canImport(NIOCore)
import NIOCore

extension ByteBuffer {

    func all() -> Data? {
        getData(at: 0, length: readableBytes)
    }
}
#endif
