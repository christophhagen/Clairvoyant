import Foundation

public protocol ServerOwner {

    func hasOwnerListAccess(with accessData: Data) -> Bool

    func hasStatusAccess(with accessData: Data) -> Bool
}
