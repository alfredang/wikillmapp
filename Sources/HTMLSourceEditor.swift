#if os(macOS)
import SwiftUI
import AppKit

/// Source view of an HTML page: a plain monospaced editor with light syntax colouring.
/// Autosaves shortly after typing stops; when the file changes on disk (the agent edited it)
/// and there are no unsaved keystrokes, it reloads.
struct HTMLSourceEditor: View {
    @EnvironmentObject var store: VaultStore
    let url: URL

    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var dirty = false

    var body: some View {
        SourceTextView(text: $text, onEdit: { dirty = true; schedule() })
            .task(id: url) { load() }
            .onChange(of: store.modificationDate(url)) { _, _ in
                if !dirty { load() }
            }
            .onDisappear { flush() }
    }

    private func load() {
        let disk = store.loadText(url)
        if disk != text { text = disk }
    }

    private func schedule() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        saveTask?.cancel()
        guard dirty else { return }
        store.save(text, to: url)
        dirty = false
    }
}

/// NSTextView wrapper tuned for code: no smart quotes/dashes, undo, monospaced font.
struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.delegate = context.coordinator
        textView.string = text
        HTMLHighlighter.apply(to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        let selection = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selection.filter { $0.rangeValue.upperBound <= (text as NSString).length }
        HTMLHighlighter.apply(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        private var highlightWork: DispatchWorkItem?

        init(_ parent: SourceTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEdit()
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak textView] in
                if let textView { HTMLHighlighter.apply(to: textView) }
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }
}

/// Colour-only HTML highlighting (no font or layout changes, so it is cheap to re-run).
enum HTMLHighlighter {
    private static let rules: [(NSRegularExpression, NSColor)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            (rx(#"</?[A-Za-z][\w:-]*|/?>"#), .systemPink),
            (rx(#"\s[A-Za-z_:][\w:.-]*(?==)"#), .systemOrange),
            (rx(#""[^"\n]*"|'[^'\n]*'"#), .systemGreen),
            (rx(#"&[A-Za-z#0-9]+;"#), .systemPurple),
            (rx(#"<!--[\s\S]*?-->"#), .secondaryLabelColor),
            (rx(#"<!DOCTYPE[^>]*>"#), .secondaryLabelColor),
        ]
    }()

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let string = storage.string
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        // Skip colouring inside very large files to keep typing responsive.
        if storage.length < 400_000 {
            for (regex, color) in rules {
                regex.enumerateMatches(in: string, range: full) { match, _, _ in
                    if let r = match?.range { storage.addAttribute(.foregroundColor, value: color, range: r) }
                }
            }
        }
        storage.endEditing()
    }
}
#endif
