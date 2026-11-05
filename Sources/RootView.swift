import SwiftUI

struct RootView: View {
    var body: some View {
        #if os(macOS)
        TopicsRootView()
            .tint(Theme.accent)
        #else
        TabView {
            VaultView()
                .tabItem { Label("Topics", systemImage: "books.vertical.fill") }
            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        #endif
    }
}
