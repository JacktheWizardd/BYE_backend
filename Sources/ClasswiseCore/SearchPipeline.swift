import Foundation

/// Fetch quick professor previews with bounded concurrency. The caller starts
/// review pagination and AI only after this first pass has finished.
@MainActor
public enum SearchPipeline {
    public static func run(
        indices: [Int],
        workerCount: Int = 2,
        lookup: @escaping @MainActor (Int) async -> Void
    ) async {
        guard !indices.isEmpty, !Task.isCancelled else { return }
        let queue = WorkQueue(indices: indices)
        let workers = min(max(1, workerCount), indices.count)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workers {
                group.addTask { @MainActor in
                    while !Task.isCancelled, let index = queue.next() {
                        await lookup(index)
                    }
                }
            }
        }
    }
}

@MainActor
private final class WorkQueue {
    private let indices: [Int]
    private var cursor = 0

    init(indices: [Int]) { self.indices = indices }

    func next() -> Int? {
        guard cursor < indices.count else { return nil }
        defer { cursor += 1 }
        return indices[cursor]
    }
}
