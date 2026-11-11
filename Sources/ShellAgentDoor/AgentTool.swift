//
//  AgentTool.swift
//  Role: What an app hands the agent door (`AgentDoor`): its tools. A tool has a name, a sentence an agent reads to decide when to
//        use it, the inputs it takes, and the code that answers it on the main actor. The door lists the tools in MCP's own shape
//        (`/v1/tools`, MCP's `tools/list`), so an app adds a tool without touching the door.
//
//  Read-only in this version: a tool looks at a window and answers; it changes nothing.
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
    public let run: @MainActor (AgentToolCall) -> AgentToolOutput

    /// `name` is lowercase letters, digits and underscores (MCP's convention, and a path segment as it stands).
    public init(name: String, title: String, summary: String, input: Input, run: @escaping @MainActor (AgentToolCall) -> AgentToolOutput) {
        precondition(Self.isValidName(name), "an agent tool's name is lowercase letters, digits and underscores: \(name)")
        self.name = name
        self.title = title
        self.summary = summary
        self.input = input
        self.run = run
    }

    nonisolated static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    /// The tool as MCP's `tools/list` describes one: name, title, description, input schema, and read-only annotations.
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
        return [
            "name": name,
            "title": title,
            "description": summary,
            "inputSchema": ["type": "object", "properties": properties, "additionalProperties": false] as [String: Any],
            "annotations": ["title": title, "readOnlyHint": true, "openWorldHint": false] as [String: Any],
        ]
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
