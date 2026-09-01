import Foundation
import SwiftData

@Model
final class PersistedCleaningSession {
    var payload: Data

    init(payload: Data) {
        self.payload = payload
    }
}
