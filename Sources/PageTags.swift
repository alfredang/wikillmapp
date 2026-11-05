import Foundation

/// Tags live in the page itself, as `<meta name="tags" content="agents, exam-prep">` in its
/// `<head>`, so they stay with the plain files and the agent can read and write them. A topic
/// or subtopic is tagged through its folder's `index.html`.
enum PageTags {
    private static let metaPattern = #"<meta\b[^>]*?\sname\s*=\s*(?:"tags"|'tags'|tags(?=[\s/>]))[^>]*>"#
    private static let contentPattern = #"\scontent\s*=\s*(?:"([^"]*)"|'([^']*)')"#

    /// Where a new tag goes, best first: after the description, the title, or the opening tags.
    private static let insertionPatterns = [
        #"<meta\b[^>]*?\sname\s*=\s*["']?description["']?[^>]*>"#,
        #"</title\s*>"#,
        #"<head\b[^>]*>"#,
        #"<html\b[^>]*>"#,
        #"<!doctype\b[^>]*>"#,
    ]

    /// `"#Claude Code"` → `"claude-code"`. Keeps what tags like `c++`, `c#` and `node.js` need.
    static func normalize(_ raw: String) -> String {
        var out = ""
        for ch in raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if ch.isWhitespace || ch == "-" {
                if !out.isEmpty, out.last != "-" { out.append("-") }
            } else if ch.isLetter || ch.isNumber || "_/+.".contains(ch) || (ch == "#" && !out.isEmpty) {
                out.append(ch)
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// A comma-separated list as typed or stored: normalized, without blanks or repeats.
    static func parseList(_ list: String) -> [String] {
        unique(list.split(separator: ",").map { normalize(String($0)) })
    }

    /// The tags of an HTML document (only `<head>` counts, so code samples never register).
    static func read(from html: String) -> [String] {
        let head = NSRange(html.startIndex..<headEnd(of: html), in: html)
        guard let rx = regex(metaPattern),
              let meta = rx.firstMatch(in: html, range: head),
              let contentRx = regex(contentPattern),
              let content = contentRx.firstMatch(in: html, range: meta.range) else { return [] }
        for group in 1...2 {
            if let range = Range(content.range(at: group), in: html) {
                return parseList(LinkIndex.decode(String(html[range])))
            }
        }
        return []
    }

    /// `html` with its tags set to `tags`. An empty list removes the meta tag.
    static func write(_ tags: [String], to html: String) -> String {
        let clean = unique(tags.map(normalize))
        let meta = #"<meta name="tags" content="\#(clean.joined(separator: ", "))">"#
        let end = headEnd(of: html)
        let head = NSRange(html.startIndex..<end, in: html)
        let matches = regex(metaPattern)?.matches(in: html, range: head) ?? []

        var out = html
        if matches.isEmpty {
            guard !clean.isEmpty else { return html }
            for pattern in insertionPatterns {
                if let found = regex(pattern)?.firstMatch(in: html, range: head),
                   let range = Range(found.range, in: html) {
                    out.insert(contentsOf: "\n" + meta, at: range.upperBound)
                    return out
                }
            }
            return meta + "\n" + html
        }
        // Back to front, so the offsets of earlier matches stay valid.
        for (i, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: out) else { continue }
            if i == 0, !clean.isEmpty {
                out.replaceSubrange(range, with: meta)
            } else {
                out.removeSubrange(wholeLine(around: range, in: out))
            }
        }
        return out
    }

    // MARK: Helpers

    private static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// End of the region where a meta tag belongs.
    private static func headEnd(of html: String) -> String.Index {
        html.range(of: #"</head\s*>|<body\b"#, options: [.regularExpression, .caseInsensitive])?.lowerBound
            ?? html.endIndex
    }

    /// `range` widened to its whole line when nothing else sits on that line.
    private static func wholeLine(around range: Range<String.Index>, in text: String) -> Range<String.Index> {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        var lower = range.lowerBound
        while lower > text.startIndex, isBlank(text[text.index(before: lower)]) {
            lower = text.index(before: lower)
        }
        var upper = range.upperBound
        while upper < text.endIndex, isBlank(text[upper]) {
            upper = text.index(after: upper)
        }
        let startsLine = lower == text.startIndex || text[text.index(before: lower)].isNewline
        guard startsLine, upper < text.endIndex, text[upper].isNewline else { return range }
        return lower..<text.index(after: upper)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
