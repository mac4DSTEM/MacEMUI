// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/Session/ResultPresentation.swift (macTEM@51c944c Sources/TEMCore/Data/ColormapKind.swift: identical enum, no differences folded in)
// Changes: made public, `nonisolated` and `Sendable` so export and display code off the main actor can read it.
// END MOVED FROM

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
