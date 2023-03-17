import Foundation
import Clairvoyant
import CBORCoding

public extension MetricConsumer {

    init(
        from url: URL,
        accessProvider: MetricRequestAccessProvider,
        session: URLSession = .shared,
        encoder: BinaryEncoder = CBOREncoder(dateEncodingStrategy: .secondsSince1970),
        decoder: BinaryDecoder = CBORDecoder()) {
            self.init(
                url: url,
                accessProvider: accessProvider,
                session: session,
                encoder: encoder,
                decoder: decoder)
    }
}
