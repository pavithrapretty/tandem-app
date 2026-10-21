//
//  SpokenLine.swift
//  HapticRemote (iPhone)
//
//  A line for the voice with the names of streets, stops and places in it
//  marked as Dutch, so "Nieuwezijds Voorburgwal" isn't read out in English.
//  VoiceOver switches to its Dutch voice for them by itself; the app's own
//  voice says them in a Dutch voice (GuidanceVoice).
//

import UIKit

/// Written like a string, with the names marked:
/// `"You've arrived at \(dutch: name)"`.
struct SpokenLine: ExpressibleByStringInterpolation {
    /// The line in pieces of one language each, in order.
    private(set) var parts: [(text: String, isDutch: Bool)] = []

    init(_ plain: String) {
        append(plain, isDutch: false)
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    init(stringInterpolation: Interpolation) {
        parts = stringInterpolation.line.parts
    }

    struct Interpolation: StringInterpolationProtocol {
        fileprivate var line = SpokenLine("")

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) {
            line.append(literal, isDutch: false)
        }

        mutating func appendInterpolation<T>(_ value: T) {
            line.append("\(value)", isDutch: false)
        }

        /// Another line, with its names still marked.
        mutating func appendInterpolation(_ other: SpokenLine) {
            for part in other.parts { line.append(part.text, isDutch: part.isDutch) }
        }

        /// A street, stop or place: said in Dutch.
        mutating func appendInterpolation(dutch name: String) {
            line.append(name, isDutch: true)
        }
    }

    /// Joins on to the last part when it is in the same language.
    private mutating func append(_ text: String, isDutch: Bool) {
        guard !text.isEmpty else { return }
        if let last = parts.last, last.isDutch == isDutch {
            parts[parts.count - 1].text += text
        } else {
            parts.append((text, isDutch))
        }
    }

    /// The text without the marks.
    var plain: String { parts.map(\.text).joined() }

    /// For VoiceOver: the names marked Dutch, so it says them in its Dutch
    /// voice. `queued`: after what it is saying, instead of over it.
    func announcement(queued: Bool = false) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for part in parts {
            text.append(NSAttributedString(string: part.text, attributes:
                part.isDutch ? [.accessibilitySpeechLanguage: "nl-NL"] : [:]))
        }
        if queued {
            text.addAttribute(.accessibilitySpeechAnnouncementPriority,
                              value: UIAccessibilityPriority.low,
                              range: NSRange(location: 0, length: text.length))
        }
        return text
    }

    /// "a, b and c".
    static func list(_ items: [SpokenLine]) -> SpokenLine {
        var line = SpokenLine("")
        for (index, item) in items.enumerated() {
            if index > 0 { line.append(index == items.count - 1 ? " and " : ", ", isDutch: false) }
            for part in item.parts { line.append(part.text, isDutch: part.isDutch) }
        }
        return line
    }
}
