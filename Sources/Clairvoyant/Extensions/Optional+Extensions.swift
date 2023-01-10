import Foundation

extension Optional {

    func unwrap(orThrow error: Error) throws -> Wrapped {
        guard let s = self else {
            throw error
        }
        return s
    }
}
