/// Pure shuffling for "Give Me Random" mode. Kept separate from the live
/// PhotoKit fetch so the ordering logic is unit-testable with a seeded
/// generator instead of the system's non-deterministic randomness.
enum RandomPhotoOrdering {
    static func shuffled(
        _ assets: [PhotoAsset],
        using generator: inout some RandomNumberGenerator
    ) -> [PhotoAsset] {
        assets.shuffled(using: &generator)
    }

    /// Picks `sampleSize` distinct indices from `0..<count`, in ascending
    /// order, without materializing anything at those indices — lets a
    /// PhotoKit fetch read only the sampled assets directly by index
    /// instead of enumerating and shuffling the entire library just to
    /// then throw most of it away.
    static func sampleIndices(
        count: Int,
        sampleSize: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [Int] {
        guard count > 0, sampleSize > 0 else { return [] }
        let boundedSampleSize = min(sampleSize, count)
        return Array(0..<count)
            .shuffled(using: &generator)
            .prefix(boundedSampleSize)
            .sorted()
    }
}
