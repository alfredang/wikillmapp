import SwiftUI

@main
struct MarkdownVaultApp: App {
    @StateObject private var store = VaultStore()
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.defaultValue.rawValue
    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .defaultValue }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                #if os(macOS)
                .onAppear { appearance.apply() }
                .onChange(of: appearanceRaw) { _, _ in appearance.apply() }
                #else
                .preferredColorScheme(appearance.colorScheme)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Page…") { post(.newPage) }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("New Subtopic…") { post(.newSubtopic) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Topic…") { post(.newTopic) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Open Library Folder…") { store.requestOpenVault() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Agent Panel") { post(.toggleAgentPanel) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { a in
                        Text(a.title).tag(a.rawValue)
                    }
                }
            }
        }
        #endif
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
