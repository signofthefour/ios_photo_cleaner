enum PhotoDecision: String, Codable, Sendable {
    case keep
    case pendingDelete
}

enum SessionDecisionError: Error, Equatable {
    case unknownAsset
    case outOfOrderAsset
}
