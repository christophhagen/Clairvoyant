import Foundation

extension TimestampedProtocol where Value: Equatable {
    
    public func isDifferentAndNewer(than other: Self) -> Bool {
        value != other.value && timestamp > other.timestamp
    }
    
    public func shouldUpdate(currentValue: Self?) -> Bool {
        guard let currentValue else {
            return true
        }
        return isDifferentAndNewer(than: currentValue)
    }
}

extension Sequence where Element: TimestampedProtocol, Element.Value: Equatable {
    
    func valuesToUpdate(currentValue: Element?) -> [Element] {
        var lastValue = currentValue
        var valuesToAdd: [Element] = []
        for value in sorted(using: { $0.timestamp }) {
            guard let last = lastValue else {
                valuesToAdd.append(value)
                lastValue = value
                continue
            }
            guard value.isDifferentAndNewer(than: last) else {
                continue
            }
            valuesToAdd.append(value)
            lastValue = value
        }
        return valuesToAdd
    }
}
