import SwiftUI

/// About tab — app card, developer card + website link, version row.
struct AboutView: View {
    private static var summary: String {
        #if os(macOS)
        "A knowledge-building app. Organise topics and subtopics as folders of self-contained HTML pages, and let the Claude Code agent research, write and maintain them as an LLM wiki."
        #else
        "Read and organise your wiki on iPhone and iPad. Topics and subtopics are folders of self-contained HTML pages, which you can write yourself or have an AI agent maintain as an LLM wiki on your computer."
        #endif
    }

    private let developerURL = URL(string: "https://www.tertiaryinfotech.com")!

    private var versionString: String { Bundle.main.appVersion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("About").font(.largeTitle.bold())

                // App card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                        Text("Wiki LLM").font(.title3.bold())
                    }
                    Text(Self.summary)
                        .foregroundStyle(Theme.mutedInk)
                }
                .appCard()

                // Developer card
                Text("DEVELOPER").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    Label("Tertiary Infotech Academy Pte Ltd", systemImage: "building.2.fill")
                        .padding(.vertical, 14)
                    Divider()
                    Link(destination: developerURL) {
                        Label("tertiaryinfotech.com", systemImage: "globe")
                    }
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                // Version row
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionString).foregroundStyle(Theme.mutedInk)
                }
                .appCard()

                Text("Your topics are plain HTML files in a folder on your device (Documents/\(TopicLibrary.folderName) by default). Nothing is locked in a proprietary store.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedInk)
            }
            .padding(22)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }
}

extension Bundle {
    /// "1.1 (3)": the marketing version and build, shown in About and under the sidebar.
    var appVersion: String {
        let s = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(s) (\(b))"
    }
}
