import Foundation

public protocol Timestampable {

}

extension Timestampable {

    public func timestamped() -> Timestamped<Self> {
        .init(value: self)
    }
}
