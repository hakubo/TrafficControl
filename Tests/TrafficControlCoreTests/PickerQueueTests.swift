import Testing
@testable import TrafficControlCore

private struct Request: Identifiable {
    let id: Int
}

@Suite struct PickerQueueTests {
    @Test func headStaysUntilResolvedAndResolutionRemovesExactRequest() {
        var queue = PickerQueue<Request>()
        let first = Request(id: 1)
        let second = Request(id: 2)
        queue.append(first)
        queue.append(second)

        #expect(queue.head?.id == 1)
        let resolvedSecond = queue.resolve(id: 2)
        #expect(resolvedSecond)
        #expect(queue.head?.id == 1)
        let resolvedFirst = queue.resolve(id: 1)
        #expect(resolvedFirst)
        #expect(queue.head == nil)
    }

    @Test func emptyChoicesRequireRecovery() {
        #expect(PickerQueue<Request>.needsRecovery(choices: []))
        #expect(!PickerQueue<Request>.needsRecovery(choices: ["browser"]))
    }
}
