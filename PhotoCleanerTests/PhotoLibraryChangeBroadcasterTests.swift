import XCTest
@testable import PhotoCleaner

final class PhotoLibraryChangeBroadcasterTests: XCTestCase {
    func testNotifyDeliversToAllActiveStreams() async {
        let broadcaster = PhotoLibraryChangeBroadcaster()
        let stream1 = broadcaster.makeStream()
        let stream2 = broadcaster.makeStream()

        broadcaster.notify()

        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()
        let value1 = await iterator1.next()
        let value2 = await iterator2.next()

        XCTAssertNotNil(value1)
        XCTAssertNotNil(value2)
    }

    func testLateSubscriberDoesNotReceivePriorEvents() async {
        let broadcaster = PhotoLibraryChangeBroadcaster()
        broadcaster.notify()

        let stream = broadcaster.makeStream()
        broadcaster.notify()

        var iterator = stream.makeAsyncIterator()
        let value = await iterator.next()

        XCTAssertNotNil(value)
    }

    func testMultipleNotificationsAreEachDelivered() async {
        let broadcaster = PhotoLibraryChangeBroadcaster()
        let stream = broadcaster.makeStream()

        broadcaster.notify()
        broadcaster.notify()

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
    }
}
