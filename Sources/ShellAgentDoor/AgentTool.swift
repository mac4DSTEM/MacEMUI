//
//  AgentTool.swift
//  Role: What an app hands the agent door (`AgentDoor`): its tools. A tool has a name, a sentence an agent reads to decide when to
//        use it, the inputs it takes, and the code that answers it on the main actor. The door lists the tools in MCP's own shape
//        (`/v1/tools`, MCP's `tools/list`), so an app adds a tool without touching the door.
//
//  Most tools look at a window and answer; they change nothing. A tool that `acts` runs something in a window as the window's own
//  controls do (starts an analysis, sets a parameter): the door runs it only while the person allows it (`AgentDoor.runsAllowed`,
//  the second switch in Settings > Agents), only through MCP, and lists it as not read-only, so the agent's client asks the person
//  before each call. No tool deletes or overwrites a file.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One open window as the door names it: `w1`, `w2`, ... in the order they appeared, and the app's own state for it.
public struct AgentWindow {
    public let id: String
    /// The app's window state (its `AppState`): a tool casts it back.
    public let state: AnyObject
}

/// One call of a tool: the window it names (resolved by the door) and its inputs.
public struct AgentToolCall {
    /// nil for a tool that takes no window.
    public let window: AgentWindow?
    /// Pixels per point for a picture, 1...3 (1 when the call names none or another value).
    public let scale: Int
    /// Every query item of the call, as sent.
    public let arguments: [String: String]
}

/// One input a tool takes besides `window` and `scale`, in MCP's schema: what an agent may send, checked before the tool runs.
public struct AgentParameter {
    public enum Kind: Equatable {
        /// A number, inside the range when one is given.
        case number(ClosedRange<Double>?)
        /// A whole number, inside the range when one is given.
        case integer(ClosedRange<Int>?)
        case boolean
        /// One of these words.
        case choice([String])
        /// Free text.
        case text
    }

    public let name: String
    public let kind: Kind
    public let summary: String
    public let required: Bool

    /// `name` follows the tools' rule: lowercase letters, digits and underscores.
    public init(_ name: String, _ kind: Kind, summary: String, required: Bool = false) {
        precondition(AgentTool.isValidName(name) && name != "window" && name != "scale", "an agent parameter's name: \(name)")
        self.name = name
        self.kind = kind
        self.summary = summary
        self.required = required
    }

    /// The schema of this input.
    var schema: [String: Any] {
        var schema: [String: Any] = ["description": summary]
        switch kind {
        case .number(let range):
            schema["type"] = "number"
            if let range { schema["minimum"] = range.lowerBound; schema["maximum"] = range.upperBound }
        case .integer(let range):
            schema["type"] = "integer"
            if let range { schema["minimum"] = range.lowerBound; schema["maximum"] = range.upperBound }
        case .boolean:
            schema["type"] = "boolean"
        case .choice(let words):
            schema["type"] = "string"
            schema["enum"] = words
        case .text:
            schema["type"] = "string"
        }
        return schema
    }

    /// Why `value` (as the door received it) is not acceptable, in one sentence an agent can act on; nil when it is.
    func problem(with value: String?) -> String? {
        guard let value else { return required ? "\(name) is required: \(summary)" : nil }
        switch kind {
        case .number(let range):
            guard let number = Double(value), number.isFinite else { return "\(name) must be a number, not \(value)." }
            if let range, !range.contains(number) { return "\(name) must be between \(range.lowerBound) and \(range.upperBound), not \(value)." }
        case .integer(let range):
            guard let number = Int(value) else { return "\(name) must be a whole number, not \(value)." }
            if let range, !range.contains(number) { return "\(name) must be between \(range.lowerBound) and \(range.upperBound), not \(value)." }
        case .boolean:
            guard value == "true" || value == "false" else { return "\(name) must be true or false, not \(value)." }
        case .choice(let words):
            guard words.contains(value) else { return "\(name) must be one of \(words.joined(separator: ", ")), not \(value)." }
        case .text:
            break
        }
        return nil
    }
}

/// A tool's answer.
public enum AgentToolOutput {
    /// A JSON object (`JSONSerialization`'s types; NaN and infinity must already be null).
    case json([String: Any])
    /// Already-encoded JSON (a `Codable` value: `AgentJSON.encoded`).
    case encodedJSON(Data)
    /// A PNG picture (`AgentJSON.png`).
    case png(Data)
    /// Not available, said in one sentence an agent can act on or pass to the person; `status` as HTTP (404 nothing yet, 409 ambiguous).
    case refusal(status: Int, message: String)
}

public struct AgentTool {
    public enum Input {
        /// The tool looks at the app as a whole.
        case noWindow
        /// The tool looks at one window.
        case window
        /// The tool draws a picture of one window, at 1x, 2x or 3x.
        case windowPicture
    }

    public let name: String
    public let title: String
    public let summary: String
    public let input: Input
    /// Its inputs besides `window` and `scale`.
    public let parameters: [AgentParameter]
    /// It changes what a window shows, as the window's own controls do (see the file's head).
    public let acts: Bool
    public let run: @MainActor (AgentToolCall) -> AgentToolOutput

    /// `name` is lowercase letters, digits and underscores (MCP's convention, and a path segment as it stands).
    public init(name: String, title: String, summary: String, input: Input, parameters: [AgentParameter] = [], acts: Bool = false,
                run: @escaping @MainActor (AgentToolCall) -> AgentToolOutput) {
        precondition(Self.isValidName(name), "an agent tool's name is lowercase letters, digits and underscores: \(name)")
        precondition(Set(parameters.map(\.name)).count == parameters.count, "agent tool \(name) names a parameter twice")
        self.name = name
        self.title = title
        self.summary = summary
        self.input = input
        self.parameters = parameters
        self.acts = acts
        self.run = run
    }

    nonisolated static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    /// The tool as MCP's `tools/list` describes one: name, title, description, input schema, and annotations (read-only, or acting
    /// but never destructive).
    var descriptor: [String: Any] {
        var properties: [String: Any] = [:]
        if input != .noWindow {
            properties["window"] = [
                "type": "string",
                "description": "The window's id from list_windows (w1, w2, ...). Leave out while exactly one window is open.",
            ]
        }
        if input == .windowPicture {
            properties["scale"] = ["type": "integer", "minimum": 1, "maximum": 3,
                                   "description": "Pixels per point: 1 (default), 2 or 3 for a sharper picture."] as [String: Any]
        }
        for parameter in parameters { properties[parameter.name] = parameter.schema }
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        let required = parameters.filter(\.required).map(\.name)
        if !required.isEmpty { schema["required"] = required }
        var annotations: [String: Any] = ["title": title, "readOnlyHint": !acts, "openWorldHint": false]
        if acts { annotations["destructiveHint"] = false; annotations["idempotentHint"] = false }
        return ["name": name, "title": title, "description": summary, "inputSchema": schema, "annotations": annotations]
    }
}

/// Helpers for a tool's answer.
public nonisolated enum AgentJSON {
    /// A finite number, or null.
    public static func number<T: BinaryFloatingPoint>(_ value: T?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return Double(value)
    }

    /// The value, or null.
    public static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    /// A `Codable` value as JSON: sorted keys, ISO 8601 dates, non-finite numbers as the strings "NaN", "Infinity", "-Infinity".
    public static func encoded<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try? encoder.encode(value)
    }

    /// The PNG bytes of `image`; nil when ImageIO cannot write it.
    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A picture as a tool's answer, or the refusal that says it could not be written.
    public static func picture(_ image: CGImage?) -> AgentToolOutput {
        guard let image, let data = png(image) else { return .refusal(status: 500, message: "The picture could not be written as PNG.") }
        return .png(data)
    }
}
