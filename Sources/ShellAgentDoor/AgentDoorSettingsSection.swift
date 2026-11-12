//
//  AgentDoorSettingsSection.swift
//  Role: The agent door's place in an app's Settings: one switch (and a second, for an app whose tools act), what the door is
//        doing, how to connect an agent, and what an agent can and cannot do, because the switch opens a listener and the person should know its reach.
//        The app keeps the preference (its own Settings store and its Reset) and opens the door when it changes.
//
//  Copy Connection Command puts the line that registers the app with Claude Code as an MCP server, address and token included,
//  on the clipboard (`AgentDoor.connectionCommand`): the person pastes it into Terminal once. New Token shuts out whoever had the old.
//  AppKit: `NSPasteboard`, the clipboard, which SwiftUI cannot write on macOS.
//

import AppKit
import SwiftUI

public struct AgentDoorSettingsSection: View {
    private let door: AgentDoor
    @Binding private var isOn: Bool
    private let canSee: String
    private let runs: Binding<Bool>?
    private let canRun: String?
    @State private var copied = false

    /// `canSee` finishes "an agent you run on this Mac can read what <app>'s windows show: ...", in the app's words. An app with
    /// tools that act passes `runs` (its preference for `AgentDoor.runsAllowed`) and `canRun`, which finishes "it can also ...".
    public init(door: AgentDoor, isOn: Binding<Bool>, canSee: String, runs: Binding<Bool>? = nil, canRun: String? = nil) {
        self.door = door
        _isOn = isOn
        self.canSee = canSee
        self.runs = runs
        self.canRun = canRun
    }

    public var body: some View {
        Section("Agent access") {
            Toggle("Let agents on this Mac look at open windows", isOn: $isOn)
                .accessibilityIdentifier("settings.agents.enabled")
            if let runs {
                Toggle("Let agents run analyses", isOn: runs)
                    .disabled(!isOn)
                    .accessibilityIdentifier("settings.agents.runs")
            }
            LabeledContent("Status", value: Self.statusText(door.status, requests: door.requestCount))
                .accessibilityIdentifier("settings.agents.status")
            LabeledContent("Connect Claude Code") {
                HStack {
                    Button(copied ? "Copied" : "Copy Connection Command") {
                        guard let command = door.connectionCommand() else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                    }
                    .disabled(door.connectionCommand() == nil)
                    .accessibilityIdentifier("settings.agents.copyCommand")
                    Button("New Token") {
                        door.makeNewToken()
                        copied = false
                    }
                    .accessibilityIdentifier("settings.agents.newToken")
                }
            }
            Text(Self.explanation(appName: door.appName, canSee: canSee, canRun: runs == nil ? nil : canRun))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: door.status) { copied = false }
    }

    /// The status row's words. Pure, so it is tested.
    static func statusText(_ status: AgentDoor.Status, requests: Int) -> String {
        switch status {
        case .off: return "Off"
        case .starting: return "Opening\u{2026}"
        case .listening(let port):
            if requests == 0 { return "On (port \(port)), no agent has asked yet" }
            return "On (port \(port)), \(requests) \(requests == 1 ? "request" : "requests") answered"
        case .failed(let why): return "Could not open: \(why)"
        }
    }

    static func explanation(appName: String, canSee: String, canRun: String? = nil) -> String {
        let reach = canRun.map {
            "With \"Let agents run analyses\" on, it can also \($0), as the window's own controls do: your agent asks you before each "
                + "step, one runs at a time, Stop in the window cancels it, and no file is deleted or overwritten. "
        } ?? "It cannot change anything. "
        return "While this is on, an agent you run on this Mac (Claude, Codex) can read what \(appName)'s windows show through MCP: "
            + "\(canSee). " + reach + "Copy the connection command and paste it into Terminal once; "
            + "it holds the door's token, so keep it to yourself, and press New Token to shut out a command you gave away. "
            + "Nothing leaves this Mac, and other computers cannot reach the app."
    }
}
