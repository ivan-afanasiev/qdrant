import Foundation
import Testing
import SweepUseCases

struct StatusBroadcastTests {
    @Test func replaysLatestValueAndCoalescesUpdates() async {
        let broadcast = StatusBroadcast(0)
        broadcast.send(1)
        var iterator = broadcast.stream().makeAsyncIterator()
        #expect(await iterator.next() == 1)
        broadcast.send(2)
        broadcast.send(3)
        #expect(await iterator.next() == 3)
    }

    @Test func concurrentSubscribersAndSendsRetainLatestValue() async {
        let broadcast = StatusBroadcast(0)
        let streams = await withTaskGroup(of: AsyncStream<Int>.self) { group in
            for value in 1...500 {
                group.addTask {
                    let stream = broadcast.stream()
                    broadcast.send(value)
                    return stream
                }
            }
            var streams: [AsyncStream<Int>] = []
            for await stream in group { streams.append(stream) }
            return streams
        }
        // All producers have finished. Every subscriber must agree with stored state,
        // regardless of which producer acquired the lock last.
        let latest = broadcast.value
        for stream in streams {
            var iterator = stream.makeAsyncIterator()
            #expect(await iterator.next() == latest)
        }
    }

    @Test func cancellationRemovesSubscriberWithoutStoppingProducer() async {
        let broadcast = StatusBroadcast(0)
        let stream = broadcast.stream()
        let task = Task {
            for await _ in stream { }
        }
        task.cancel()
        await task.value
        #expect(broadcast.subscriberCount == 0)
        broadcast.send(1)
        var iterator = broadcast.stream().makeAsyncIterator()
        #expect(await iterator.next() == 1)
    }
}
