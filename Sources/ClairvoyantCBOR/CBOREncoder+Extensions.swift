import Foundation
import Clairvoyant
import CBORCoding

extension CBOREncoder: BinaryEncoder {

    /// The length of the binary data of a timestamp encoded in CBOR
    public var encodedTimestampLength: Int { 9 }

}
