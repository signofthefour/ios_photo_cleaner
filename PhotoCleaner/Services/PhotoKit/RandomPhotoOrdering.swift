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
}
