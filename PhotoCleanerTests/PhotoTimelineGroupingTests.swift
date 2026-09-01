import Foundation
import XCTest
@testable import PhotoCleaner

final class PhotoTimelineGroupingTests: XCTestCase {
    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testAssetsInSameMonthAreGroupedTogether() {
        let calendar = fixedCalendar()
        let assets = [
            PhotoTimelineGrouping.AssetDescriptor(id: "a", creationDate: date(2025, 3, 1, calendar: calendar)),
            PhotoTimelineGrouping.AssetDescriptor(id: "b", creationDate: date(2025, 3, 15, calendar: calendar)),
            PhotoTimelineGrouping.AssetDescriptor(id: "c", creationDate: date(2025, 3, 31, calendar: calendar))
        ]

        let groups = PhotoTimelineGrouping.groups(for: assets, calendar: calendar)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, "2025-03")
        XCTAssertEqual(groups.first?.title, "March 2025")
        XCTAssertEqual(groups.first?.photoCount, 3)
    }

    func testGroupsAreSortedNewestFirst() {
        let calendar = fixedCalendar()
        let assets = [
            PhotoTimelineGrouping.AssetDescriptor(id: "a", creationDate: date(2024, 1, 1, calendar: calendar)),
            PhotoTimelineGrouping.AssetDescriptor(id: "b", creationDate: date(2025, 6, 1, calendar: calendar)),
            PhotoTimelineGrouping.AssetDescriptor(id: "c", creationDate: date(2025, 1, 1, calendar: calendar))
        ]

        let groups = PhotoTimelineGrouping.groups(for: assets, calendar: calendar)

        XCTAssertEqual(groups.map(\.id), ["2025-06", "2025-01", "2024-01"])
    }

    func testMonthIntervalCoversTheEntireCalendarMonth() {
        let calendar = fixedCalendar()
        let assets = [
            PhotoTimelineGrouping.AssetDescriptor(id: "a", creationDate: date(2025, 3, 15, calendar: calendar))
        ]

        let group = PhotoTimelineGrouping.groups(for: assets, calendar: calendar).first

        XCTAssertEqual(group?.interval.start, date(2025, 3, 1, calendar: calendar))
        XCTAssertEqual(group?.interval.end, date(2025, 4, 1, calendar: calendar))
    }

    func testAssetsWithoutCreationDateAreGroupedAsUnknown() {
        let calendar = fixedCalendar()
        let assets = [
            PhotoTimelineGrouping.AssetDescriptor(id: "a", creationDate: nil),
            PhotoTimelineGrouping.AssetDescriptor(id: "b", creationDate: date(2025, 3, 1, calendar: calendar)),
            PhotoTimelineGrouping.AssetDescriptor(id: "c", creationDate: nil)
        ]

        let groups = PhotoTimelineGrouping.groups(for: assets, calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        let unknown = groups.first { $0.id == PhotoTimelineGrouping.unknownGroupID }
        XCTAssertEqual(unknown?.photoCount, 2)
        XCTAssertEqual(unknown?.title, "Unknown Date")
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(PhotoTimelineGrouping.groups(for: [], calendar: fixedCalendar()).isEmpty)
    }
}
