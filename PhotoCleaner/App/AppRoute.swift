enum AppRoute: Hashable {
    case sourcePicker
    case cleaner(CleaningSource)
    case deletionReview
    case settings
}
