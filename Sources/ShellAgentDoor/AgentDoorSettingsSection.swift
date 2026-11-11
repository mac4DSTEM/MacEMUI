//
//  AgentDoorSettingsSection.swift
//  Role: The agent door's place in an app's Settings: one switch, what the door is doing, and one sentence on what an agent can
//        and cannot do, because the switch opens a listener and the person should know its reach before turning it on.
//        The app keeps the preference (its own Settings store and its Reset) and opens the door when it changes.
//

import SwiftUI

public struct AgentDoorSettingsSection: View {
    private let door: AgentDoor
    @Binding private var isOn: Bool
    private let canSee: String

    /// `canSee` finishes "an agent you run on this Mac can read what <app>'s windows show: ...", in the app's words.
    public init(door: AgentDoor, isOn: Binding<Bool>, canSee: String) {
        self.door = door
        _isOn = isOn
        self.canSee = canSee
    }

    public var body: some View {
        Section("Agent access") {
            Toggle("Let agents on this Mac look at open windows", isOn: $isOn)
                .accessibilityIdentifier("settings.agents.enabled")
            LabeledContent("Status", value: Self.statusText(door.status, requests: door.requestCount))
                .accessibilityIdentifier("settings.agents.status")
            Text(Self.explanation(appName: door.appName, canSee: canSee))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    static func explanation(appName: String, canSee: String) -> String {
        "While this is on, an agent you run on this Mac (Claude, Codex) can read what \(appName)'s windows show through the "
            + "macEM MCP bridge: \(canSee). It cannot change anything. Nothing leaves this Mac, and other computers cannot reach the app."
    }
}
