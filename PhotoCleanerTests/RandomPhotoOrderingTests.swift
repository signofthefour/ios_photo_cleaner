import XCTest
@testable import PhotoCleaner

/// Deterministic RNG so shuffle tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

final class RandomPhotoOrderingTests: XCTestCase {
    private func makeAssets(_ count: Int) -> [PhotoAsset] {
        (1...count).map {
            PhotoAsset(id: "asset-\($0)", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
        }
    }

    func testShuffledContainsExactlyTheSameAssets() {
        let assets = makeAssets(20)
        var generator = SeededGenerator(seed: 42)

        let shuffled = RandomPhotoOrdering.shuffled(assets, using: &generator)

        XCTAssertEqual(shuffled.count, assets.count)
        XCTAssertEqual(Set(shuffled.map(\.id)), Set(assets.map(\.id)))
    }

    func testShuffledChangesOrderForMultipleAssets() {
        let assets = makeAssets(20)
        var generator = SeededGenerator(seed: 42)

        let shuffled = RandomPhotoOrdering.shuffled(assets, using: &generator)

        XCTAssertNotEqual(shuffled.map(\.id), assets.map(\.id))
    }

    func testShuffledHandlesEmptyAndSingleElementInput() {
        var generator = SeededGenerator(seed: 1)

        XCTAssertEqual(RandomPhotoOrdering.shuffled([], using: &generator), [])

        let single = makeAssets(1)
        XCTAssertEqual(RandomPhotoOrdering.shuffled(single, using: &generator), single)
    }

    func testSampleIndicesReturnsDistinctInBoundsIndicesInAscendingOrder() {
        var generator = SeededGenerator(seed: 7)

        let indices = RandomPhotoOrdering.sampleIndices(count: 10_000, sampleSize: 200, using: &generator)

        XCTAssertEqual(indices.count, 200)
        XCTAssertEqual(Set(indices).count, 200)
        XCTAssertEqual(indices, indices.sorted())
        XCTAssertTrue(indices.allSatisfy { (0..<10_000).contains($0) })
    }

    func testSampleIndicesCapsAtCountWhenSampleSizeIsLarger() {
        var generator = SeededGenerator(seed: 7)

        let indices = RandomPhotoOrdering.sampleIndices(count: 5, sampleSize: 200, using: &generator)

        XCTAssertEqual(Set(indices), Set(0..<5))
    }

    func testSampleIndicesHandlesZeroCountOrSampleSize() {
        var generator = SeededGenerator(seed: 7)

        XCTAssertEqual(RandomPhotoOrdering.sampleIndices(count: 0, sampleSize: 200, using: &generator), [])
        XCTAssertEqual(RandomPhotoOrdering.sampleIndices(count: 10, sampleSize: 0, using: &generator), [])
    }
}
