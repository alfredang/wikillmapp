import Foundation

/// A node in the vault file tree. Directories carry `children`; files have `nil`.
struct FileNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    static let editableExtensions: Set<String> = ["md", "markdown", "mdown", "txt", "text", "csv"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "svg"]

    var ext: String { url.pathExtension.lowercased() }
    var isMarkdown: Bool { ["md", "markdown", "mdown"].contains(ext) }
    var isEditable: Bool { Self.editableExtensions.contains(ext) }
    var isImage: Bool { Self.imageExtensions.contains(ext) }

    var systemImage: String {
        if isDirectory { return name == "raw" ? "tray.full" : "folder" }
        if ["html", "htm"].contains(ext) { return "doc.richtext" }
        if isMarkdown { return "doc.text" }
        if isImage { return "photo" }
        if ext == "pdf" { return "doc.viewfinder" }
        return "doc"
    }
}
