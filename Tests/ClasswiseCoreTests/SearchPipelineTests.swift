import XCTest
@testable import ClasswiseCore

final class SearchPipelineTests: XCTestCase {
    @MainActor
    func testDefaultConcurrencyIsTwoAndProcessesEachItemOnce() async {
        var active = 0
        var maximum = 0
        var completed: [Int] = []

        await SearchPipeline.run(indices: Array(0..<12)) { index in
            active += 1
            maximum = max(maximum, active)
            try? await Task.sleep(for: .milliseconds(5))
            completed.append(index)
            active -= 1
        }

        XCTAssertEqual(maximum, 2)
        XCTAssertEqual(active, 0)
        XCTAssertEqual(completed.sorted(), Array(0..<12))
    }

    @MainActor
    func testCompletedPreviewsAreAvailableBeforeThePassFinishes() async {
        let firstCompleted = PipelineGate()
        let releaseOthers = PipelineGate()
        var completed: [Int] = []
        var passFinished = false
        let task = Task { @MainActor in
            await SearchPipeline.run(indices: [0, 1, 2]) { index in
                if index != 0 { await releaseOthers.wait() }
                completed.append(index)
                if index == 0 { firstCompleted.open() }
            }
            passFinished = true
        }

        await firstCompleted.wait()
        XCTAssertEqual(completed, [0])
        XCTAssertFalse(passFinished)
        releaseOthers.open()
        await task.value
        XCTAssertTrue(passFinished)
        XCTAssertEqual(completed.sorted(), [0, 1, 2])
    }

    @MainActor
    func testCancellationStopsTakingQueuedJobs() async {
        let twoStarted = PipelineGate()
        let releaseLookups = PipelineGate()
        var started: [Int] = []
        var cancelledInFlight = 0
        let task = Task { @MainActor in
            await SearchPipeline.run(indices: Array(0..<10)) { index in
                started.append(index)
                if started.count == 2 { twoStarted.open() }
                await releaseLookups.wait()
                if Task.isCancelled { cancelledInFlight += 1 }
            }
        }

        await twoStarted.wait()
        task.cancel()
        releaseLookups.open()
        await task.value
        XCTAssertEqual(started.sorted(), [0, 1])
        XCTAssertEqual(cancelledInFlight, 2)
    }

    @MainActor
    func testAnAlreadyCancelledPassDoesNotStartLookups() async {
        let start = PipelineGate()
        var calls = 0
        let task = Task { @MainActor in
            await start.wait()
            await SearchPipeline.run(indices: [0, 1]) { _ in calls += 1 }
        }
        task.cancel()
        start.open()
        await task.value
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testEmptyPassDoesNotInvokeLookup() async {
        var calls = 0
        await SearchPipeline.run(indices: []) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testCustomWorkerCountsAreBoundedByAvailableWork() async {
        for requested in [-2, 0, 1, 3, 100] {
            var active = 0
            var maximum = 0
            var completed = 0
            await SearchPipeline.run(indices: Array(0..<7), workerCount: requested) { _ in
                active += 1
                maximum = max(maximum, active)
                try? await Task.sleep(for: .milliseconds(5))
                active -= 1
                completed += 1
            }
            XCTAssertEqual(maximum, min(max(1, requested), 7), "Requested \(requested) workers")
            XCTAssertEqual(completed, 7)
        }
    }
}

/// A deterministic barrier so ordering and cancellation checks do not depend on
/// arbitrarily long sleeps or the machine's scheduling speed.
@MainActor
private final class PipelineGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
