//
//  PeriodicTable.swift
//  Role: the periodic table of the spectroscopy rooms' element control (design 2026-10-22; moved from mac4DSTEM's PeriodicTableView / spec 2 D-9): 18 columns, periods 1 to 6, the f-block
//        and period 7 folded below. States are told by fill only: mapped (accent fill), proposed (accent outline), fit only (hollow), off (a quiet well), not detectable (dim). A click toggles
//        Quantify and Off; a right-click gives the role (Quantify, Fit only, Off) and, per line family, the lines to check with their energies, and "Default lines". The table knows nothing of
//        a session: the app answers each question through `PeriodicTableActions`.
//

import SwiftUI

/// What a cell shows: mapped (quantify), fit only, off, proposed by the proposer (with the role it suggests), or not detectable (with the reason).
public nonisolated enum PeriodicCellState: Equatable, Sendable {
    case quantify, fitOnly, off
    case suggested(String)
    case unavailable(String)
}

/// The role an element can have.
public nonisolated enum ElementRoleChoice: String, CaseIterable, Identifiable, Sendable {
    case quantify, fitOnly, off

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .quantify: "Quantify"
        case .fitOnly: "Fit only"
        case .off: "Off"
        }
    }
}

/// One line of a family the menu offers: its id, its words ("Kα 1.487 keV") and whether it is checked.
public struct ElementLineChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var isChecked: Bool
    public init(id: String, title: String, isChecked: Bool) { self.id = id; self.title = title; self.isChecked = isChecked }
}

/// A line family of an element ("K", "L", "M") with its lines.
public struct ElementLineFamily: Identifiable, Equatable, Sendable {
    public var family: String
    public var isSelected: Bool
    public var lines: [ElementLineChoice]
    public var id: String { family }
    public init(family: String, isSelected: Bool, lines: [ElementLineChoice]) { self.family = family; self.isSelected = isSelected; self.lines = lines }
}

/// The questions the table asks and the changes it reports; the app answers from its own model.
public struct PeriodicTableActions {
    public var state: (Int) -> PeriodicCellState
    public var role: (Int) -> ElementRoleChoice
    public var click: (Int) -> Void
    public var setRole: (Int, ElementRoleChoice) -> Void
    public var hover: (Int?) -> Void
    public var families: (Int) -> [ElementLineFamily]
    public var setFamily: (Int, String) -> Void
    public var toggleLine: (Int, String) -> Void
    public var resetLines: (Int) -> Void
    public var hasChosenLines: (Int) -> Bool
    /// The atomic numbers mapped now, for VoiceOver's rotor.
    public var mapped: () -> [Int]

    public init(state: @escaping (Int) -> PeriodicCellState, role: @escaping (Int) -> ElementRoleChoice, click: @escaping (Int) -> Void,
                setRole: @escaping (Int, ElementRoleChoice) -> Void, hover: @escaping (Int?) -> Void = { _ in },
                families: @escaping (Int) -> [ElementLineFamily] = { _ in [] }, setFamily: @escaping (Int, String) -> Void = { _, _ in },
                toggleLine: @escaping (Int, String) -> Void = { _, _ in }, resetLines: @escaping (Int) -> Void = { _ in },
                hasChosenLines: @escaping (Int) -> Bool = { _ in false }, mapped: @escaping () -> [Int] = { [] }) {
        self.state = state; self.role = role; self.click = click; self.setRole = setRole; self.hover = hover
        self.families = families; self.setFamily = setFamily; self.toggleLine = toggleLine; self.resetLines = resetLines
        self.hasChosenLines = hasChosenLines; self.mapped = mapped
    }
}

/// The element symbols by atomic number, and the table's shape; pure, so a test holds them.
public nonisolated enum PeriodicTableGrid {
    public static let symbols = ["H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca", "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
        "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd", "Pm", "Sm",
        "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg", "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu",
        "Am", "Cm", "Bk", "Cf", "Es", "Fm", "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Nh", "Fl", "Mc", "Lv", "Ts", "Og"]

    public static func symbol(_ z: Int) -> String { symbols.indices.contains(z - 1) ? symbols[z - 1] : "" }

    public static let columns = 18
    public static let gap: CGFloat = 2
    /// Period 1 to 6, group 1 to 18; nil is an empty place (period 6 column 2 is the lanthanide fold's slot).
    public static let rows: [[Int?]] = [
        [1] + [Int?](repeating: nil, count: 16) + [2],
        [3, 4] + [Int?](repeating: nil, count: 10) + Array(5...10).map { Optional($0) },
        [11, 12] + [Int?](repeating: nil, count: 10) + Array(13...18).map { Optional($0) },
        Array(19...36).map { Optional($0) },
        Array(37...54).map { Optional($0) },
        [55, 56, nil] + Array(72...86).map { Optional($0) },
    ]
    /// The lanthanides, period 7 and the actinides, folded below the table.
    public static let folded: [Int] = Array(57...71) + Array(87...118)
    public static let minimumWidth: CGFloat = 18 * 10 + 17 * 2
    public static let idealWidth: CGFloat = 248

    public static func cellSize(width: CGFloat) -> CGFloat { (max(width, minimumWidth) - CGFloat(columns - 1) * gap) / CGFloat(columns) }
    /// Half the cell, clamped to 9...13 points.
    public static func symbolSize(cell: CGFloat) -> CGFloat { min(max(0.5 * cell, 9), 13) }
    public static func height(width: CGFloat, rowCount: Int) -> CGFloat {
        rowCount > 0 ? CGFloat(rowCount) * cellSize(width: width) + CGFloat(rowCount - 1) * gap : 0
    }
}

/// Lays its subviews out in 18 columns of square cells that fill the proposed width.
struct PeriodicGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PeriodicTableGrid.idealWidth
        let width = max(w, PeriodicTableGrid.minimumWidth)
        let rows = (subviews.count + PeriodicTableGrid.columns - 1) / PeriodicTableGrid.columns
        return CGSize(width: width, height: PeriodicTableGrid.height(width: width, rowCount: rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = PeriodicTableGrid.cellSize(width: bounds.width)
        for (i, view) in subviews.enumerated() {
            let col = i % PeriodicTableGrid.columns, row = i / PeriodicTableGrid.columns
            view.place(at: CGPoint(x: bounds.minX + CGFloat(col) * (cell + PeriodicTableGrid.gap), y: bounds.minY + CGFloat(row) * (cell + PeriodicTableGrid.gap)),
                       proposal: ProposedViewSize(width: cell, height: cell))
        }
    }
}

public struct PeriodicTable: View {
    private let actions: PeriodicTableActions
    @State private var foldedOpen = false
    @State private var width = PeriodicTableGrid.idealWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rotorSpace

    public init(actions: PeriodicTableActions) { self.actions = actions }

    public var body: some View {
        VStack(alignment: .leading, spacing: PeriodicTableGrid.gap) {
            PeriodicGridLayout {
                ForEach(Array(PeriodicTableGrid.rows.joined().enumerated()), id: \.offset) { _, z in
                    if let z { cell(z) } else { Color.clear }
                }
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { foldedOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(foldedOpen ? 90 : 0)).accessibilityHidden(true)
                    Text("Lanthanides and actinides")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(foldedOpen ? "Expanded" : "Collapsed")
            .padding(.top, 4)
            .help("Lanthanides, and period 7 with the actinides")
            if foldedOpen {
                PeriodicGridLayout { ForEach(PeriodicTableGrid.folded, id: \.self) { cell($0) } }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("periodicTable")
        .accessibilityRotor("Mapped") {
            ForEach(actions.mapped(), id: \.self) { z in AccessibilityRotorEntry(Text(PeriodicTableGrid.symbol(z)), id: z, in: rotorSpace) }
        }
    }

    private func cell(_ z: Int) -> some View {
        let state = actions.state(z)
        let sym = PeriodicTableGrid.symbol(z)
        let size = PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: width))
        return Button { actions.click(z) } label: {
            Text(sym)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Self.ink(state))
                .background(RoundedRectangle(cornerRadius: Self.corner).fill(Self.fill(state)))
                .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(Self.border(state), lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in actions.hover(inside ? z : nil) }
        .contextMenu {
            if case .unavailable(let reason) = state { Text(reason) } else {
                ForEach(ElementRoleChoice.allCases) { r in
                    Toggle(r.title, isOn: Binding(get: { actions.role(z) == r }, set: { _ in actions.setRole(z, r) }))
                }
                let families = actions.families(z)
                if !families.isEmpty {
                    Divider()
                    Menu("Lines") {
                        ForEach(families) { f in
                            Toggle("\(f.family) lines", isOn: Binding(get: { f.isSelected }, set: { _ in actions.setFamily(z, f.family) }))
                            ForEach(f.lines) { line in
                                Toggle(line.title, isOn: Binding(get: { line.isChecked }, set: { _ in actions.toggleLine(z, line.id) }))
                            }
                            Divider()
                        }
                        Button("Default lines") { actions.resetLines(z) }.disabled(!actions.hasChosenLines(z))
                    }
                }
            }
        }
        .help(Self.help(state, sym))
        .accessibilityLabel(sym)
        .accessibilityValue(Self.describe(state))
        .accessibilityActions {
            if case .unavailable = state {} else { ForEach(ElementRoleChoice.allCases) { r in Button(r.title) { actions.setRole(z, r) } } }
        }
        .accessibilityRotorEntry(id: z, in: rotorSpace)
        .accessibilityIdentifier("periodicTable.\(sym)")
    }

    private static let corner: CGFloat = 3

    static func fill(_ s: PeriodicCellState) -> Color {
        switch s {
        case .quantify: .accentColor
        case .off: Color.primary.opacity(0.06)
        case .fitOnly, .suggested, .unavailable: .clear
        }
    }
    static func ink(_ s: PeriodicCellState) -> Color {
        switch s {
        case .quantify: .white
        case .unavailable: Color.primary.opacity(0.25)
        default: .primary
        }
    }
    static func border(_ s: PeriodicCellState) -> Color {
        switch s {
        case .suggested: .accentColor
        case .fitOnly: Color.primary.opacity(0.6)
        default: .clear
        }
    }
    nonisolated static func help(_ s: PeriodicCellState, _ sym: String) -> String {
        switch s {
        case .suggested(let r): "\(sym) · proposed (\(r)) — click to map"
        case .unavailable(let r): "\(sym): \(r)"
        default: "\(sym) · \(describe(s)) — click toggles, right-click for more"
        }
    }
    nonisolated static func describe(_ s: PeriodicCellState) -> String {
        switch s {
        case .quantify: "mapped"
        case .fitOnly: "fit only"
        case .off: "off"
        case .suggested(let r): "proposed, \(r)"
        case .unavailable: "not detectable"
        }
    }
}
