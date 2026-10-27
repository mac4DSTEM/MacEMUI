import Foundation

public nonisolated enum ColormapKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case viridis
    case inferno
    case gray
    case rdbu

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .viridis: return "Viridis"
        case .inferno: return "Inferno"
        case .gray: return "Gray"
        case .rdbu: return "RdBu (diverging)"
        }
    }

    public var isDiverging: Bool { self == .rdbu }
}
