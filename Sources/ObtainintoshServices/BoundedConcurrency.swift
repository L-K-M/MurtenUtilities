import Foundation

/// Runs `operation` over `inputs` with at most `limit` in flight and returns
/// the results in input order, whatever order they finish in: callers match
/// results to programs by position. Bounded so a long list cannot open a
/// connection per program at once or trip a forge's rate limiting.
public func boundedOrderedMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], limit: Int, _ operation: @escaping @Sendable (Input) async -> Output
) async -> [Output] {
    precondition(limit > 0, "bounded operation limit must be positive")
    guard !inputs.isEmpty else { return [] }

    var results = [Output?](repeating: nil, count: inputs.count)
    await withTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        while next < min(limit, inputs.count) {
            let index = next
            let input = inputs[index]
            group.addTask { (index, await operation(input)) }
            next += 1
        }
        while let (index, output) = await group.next() {
            results[index] = output
            guard next < inputs.count else { continue }
            let nextIndex = next
            let input = inputs[nextIndex]
            group.addTask { (nextIndex, await operation(input)) }
            next += 1
        }
    }
    return results.map { $0! }
}
