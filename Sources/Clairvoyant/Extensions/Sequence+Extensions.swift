import Foundation

extension Sequence {

    func sorted<T>(using conversion: (Element) -> T) -> [Element] where T: Comparable {
        sorted { conversion($0) < conversion($1) }
    }
}
