import Foundation

extension Sequence {

    func sorted<T>(using conversion: (Element) -> T) -> [Element] where T: Comparable {
        sorted { conversion($0) < conversion($1) }
    }

    func asyncMap<Transformed>(transform: @escaping (Element) async throws -> Transformed) async rethrows -> [Transformed] {
        try await withThrowingTaskGroup(of: Transformed.self) { group in
            for element in self {
                group.addTask { try await transform(element) }
            }
            var result: [Transformed] = []
            for try await element in group {
                result.append(element)
            }
            return result
        }
    }
}
