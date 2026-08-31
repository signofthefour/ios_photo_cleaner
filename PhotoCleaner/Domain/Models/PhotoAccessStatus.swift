enum PhotoAccessStatus: String, Codable, Sendable {
    case notDetermined
    case limited
    case authorized
    case denied
    case restricted
}
