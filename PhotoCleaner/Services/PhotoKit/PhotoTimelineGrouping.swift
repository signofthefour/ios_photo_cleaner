import Foundation

/// Buckets photo assets into by-month `TimelineGroup`s. Pure and
/// framework-independent (no `PHAsset`) so it is unit-testable without a
/// real photo library.
enum PhotoTimelineGrouping {
    /// The minimal description of an asset needed to bucket it.
    struct AssetDescriptor: Sendable {
        let id: String
        let creationDate: Date?
    }

    /// Group id used for assets with no `creationDate`.
    static let unknownGroupID = "unknown-date"

    static func groups(
        for assets: [AssetDescriptor],
        calendar: Calendar = .current
    ) -> [TimelineGroup] {
        var buckets: [DateComponents: (interval: DateInterval, count: Int)] = [:]
        var unknownCount = 0

        for asset in assets {
            guard let date = asset.creationDate else {
                unknownCount += 1
                continue
            }

            let components = calendar.dateComponents([.year, .month], from: date)
            guard
                let monthStart = calendar.date(from: components),
                let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart)
            else { continue }

            let interval = DateInterval(start: monthStart, end: monthEnd)
            if let existing = buckets[components] {
                buckets[components] = (existing.interval, existing.count + 1)
            } else {
                buckets[components] = (interval, 1)
            }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.dateFormat = "LLLL yyyy"

        var result = buckets
            .map { components, bucket in
                TimelineGroup(
                    id: monthGroupID(for: components),
                    title: formatter.string(from: bucket.interval.start),
                    interval: bucket.interval,
                    photoCount: bucket.count
                )
            }
            .sorted { $0.interval.start > $1.interval.start }

        if unknownCount > 0 {
            result.append(
                TimelineGroup(
                    id: unknownGroupID,
                    title: "Unknown Date",
                    interval: DateInterval(start: .distantPast, duration: 0),
                    photoCount: unknownCount
                )
            )
        }

        return result
    }

    private static func monthGroupID(for components: DateComponents) -> String {
        "\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))"
    }
}
