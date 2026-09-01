import XCTest
@testable import PhotoCleaner

final class SwipeCardInteractionTests: XCTestCase {
    func testCommitRequiresOneQuarterOfMeasuredWidthAndIncludesBoundary() {
        XCTAssertNil(SwipeCardInteraction.commitDirection(translation: 79, cardWidth: 320))
        XCTAssertEqual(
            SwipeCardInteraction.commitDirection(translation: 80, cardWidth: 320),
            .keep
        )
        XCTAssertEqual(
            SwipeCardInteraction.commitDirection(translation: -80, cardWidth: 320),
            .delete
        )
    }

    func testRotationIsProportionalAndCappedInBothDirections() {
        XCTAssertEqual(
            SwipeCardInteraction.rotationDegrees(translation: 80, cardWidth: 320),
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SwipeCardInteraction.rotationDegrees(translation: 640, cardWidth: 320),
            8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SwipeCardInteraction.rotationDegrees(translation: -640, cardWidth: 320),
            -8,
            accuracy: 0.001
        )
    }

    func testStampUsesDirectionAndDistanceOpacity() {
        XCTAssertNil(SwipeCardInteraction.stamp(translation: 0, cardWidth: 320))
        XCTAssertEqual(
            SwipeCardInteraction.stamp(translation: 40, cardWidth: 320),
            .init(direction: .keep, opacity: 0.5)
        )
        XCTAssertEqual(
            SwipeCardInteraction.stamp(translation: -80, cardWidth: 320),
            .init(direction: .delete, opacity: 1)
        )
    }

    func testInvalidCardWidthCannotCommitOrRotate() {
        XCTAssertNil(SwipeCardInteraction.commitDirection(translation: 100, cardWidth: 0))
        XCTAssertEqual(SwipeCardInteraction.rotationDegrees(translation: 100, cardWidth: 0), 0)
    }

    func testCommitGateAcceptsOnlyOneCommitUntilReset() {
        var gate = SwipeCommitGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        gate.reset()
        XCTAssertTrue(gate.begin())
    }
}
