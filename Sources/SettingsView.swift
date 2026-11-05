import SwiftUI

/// Settings — library management and display preferences.
struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    @AppStorage("settings.previewDefault") private var previewDefault = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.defaultValue.rawValue

    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle.bold())

                // Vault
                Text("LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Current Library", systemImage: "books.vertical.fill")
                        Spacer()
                        Text(store.vaultName).foregroundStyle(Theme.mutedInk)
                        Button {
                            renameText = store.vaultName
                            showRename = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Rename this library")
                        .disabled(store.rootURL == nil)
                    }
                    .padding(.vertical, 14)
                    Divider()
                    Button {
                        store.requestOpenVault()
                    } label: {
                        Label("Open Another Library Folder…", systemImage: "folder.badge.plus")
                    }
                    .padding(.vertical, 14)
                    Divider()
                    Button {
                        store.openDefaultLibrary()
                    } label: {
                        Label("Open Default Library (Documents/\(TopicLibrary.folderName))", systemImage: "house")
                    }
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                // Recent vaults — one-click switching, Obsidian-style.
                let others = store.recentVaults.filter { $0.standardizedFileURL != store.rootURL?.standardizedFileURL }
                if !others.isEmpty {
                    Text("RECENT LIBRARIES").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(others.enumerated()), id: \.element) { index, url in
                            if index > 0 { Divider() }
                            HStack {
                                Button {
                                    store.openVault(at: url)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(store.displayName(for: url), systemImage: "folder")
                                        Text(url.path)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.mutedInk)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    store.removeRecent(url)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from recent list")
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                }

                // Appearance
                Text("APPEARANCE").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ForEach(AppAppearance.allCases) { option in
                            ThemeSwatch(option: option, selected: appearanceRaw == option.rawValue) {
                                appearanceRaw = option.rawValue
                            }
                        }
                    }
                    Text("Light is the default. Pages in the library switch with the app (they use prefers-color-scheme).")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedInk)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                // Display
                Text("DISPLAY").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $store.showHiddenFiles) {
                        Label("Show Hidden Files", systemImage: "eye")
                    }
                    .padding(.vertical, 12)
                    Divider()
                    Toggle(isOn: $previewDefault) {
                        Label("Open Markdown Files in Preview", systemImage: "doc.text.image")
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                .tint(Theme.accent)
            }
            .padding(22)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        // Bridge the importer used elsewhere — settings just toggles the request flag.
    }
}

/// A clickable preview tile for one appearance option.
private struct ThemeSwatch: View {
    let option: AppAppearance
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    switch option {
                    case .light:  tile(bg: .white, fg: Color(hex: 0x1B1A22))
                    case .dark:   tile(bg: Color(hex: 0x17161C), fg: Color(hex: 0xECEBF2))
                    case .system:
                        HStack(spacing: 0) {
                            tile(bg: .white, fg: Color(hex: 0x1B1A22))
                            tile(bg: Color(hex: 0x17161C), fg: Color(hex: 0xECEBF2))
                        }
                    }
                }
                .frame(width: 112, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2.5 : 1))
                Label(option.title, systemImage: option.symbol)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(bg: Color, fg: Color) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.primary).frame(width: 30, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.75)).frame(width: 52, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(fg.opacity(0.35)).frame(width: 40, height: 5)
            }
            .padding(10)
        }
    }
}
