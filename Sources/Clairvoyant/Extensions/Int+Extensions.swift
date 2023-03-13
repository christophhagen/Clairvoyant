import Foundation

extension Int {

    static func random() -> Int {
        random(in: .min ... .max)
    }
}
