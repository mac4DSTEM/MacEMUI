// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/UI/BottomWorkspace.swift (`OutputPane`) (macTEM@51c944c macTEM/UI/WorkspaceView.swift folded in: `OutputPane` (same body, header written inline); macTEM's accessibility identifier "process.output" and Clear's `lines.isEmpty` test not taken, mac4DSTEM's identifiers kept)
// Changes: made public; reads an `ActivityLog` passed in instead of AppState; the header is `ProcessPaneHeader`
// END MOVED FROM

import Foundation
import SwiftUI

/// The rolling output log, auto-scrolled to the latest line (mac4DSTEM ADR 034: copy,
/// search and filter are later work). Both apps register it as their Output process tab:
/// `ProcessTab.output { OutputPane(log: activityLog) }`.
public struct OutputPane: View {
    private let log: ActivityLog

    public init(log: ActivityLog) {
        self.log = log
    }

    public var body: some View {
        VStack(spacing: 0) {
            ProcessPaneHeader(title: "Output") {
                Button("Clear") { log.clear() }
                    .disabled(log.messages.isEmpty)
                    .help("Clears the output log")
                    .accessibilityIdentifier("bottomWorkspace.output.clear")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(log.lines) { line in
                            Text(line.text)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, LayoutPolicy.infobarHorizontalPadding)
                    .padding(.vertical, 4)
                }
                .onChange(of: log.lines.last?.id) {
                    if let target = ActivityLog.scrollTarget(for: log.lines) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
                .onAppear {
                    // `.onChange` never fires the first time the panel
                    // appears; the rows may not exist yet on this tick, so
                    // the scroll is deferred a runloop turn.
                    guard let target = ActivityLog.scrollTarget(for: log.lines) else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("bottomWorkspace.output")
    }
}
