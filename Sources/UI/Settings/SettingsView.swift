import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let store: ClipboardStore

    /// Регистрация хоткея может провалиться (комбинация занята) —
    /// показываем это здесь, а не молча игнорируем.
    let hotKeyError: String?

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings, hotKeyError: hotKeyError)
                .tabItem { Label("General", systemImage: "gearshape") }

            StorageSettingsTab(settings: settings, store: store)
                .tabItem { Label("Storage", systemImage: "internaldrive") }

            AppearanceSettingsTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            BehaviorSettingsTab(settings: settings)
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480)
        .padding(.top, 12)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    let hotKeyError: String?

    @State private var launchAtLoginNeedsApproval = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if launchAtLoginNeedsApproval {
                    Text("Approve ClipFlow in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Global shortcut") {
                    ShortcutRecorderView(combo: $settings.hotKey)
                        .frame(width: 130, height: 24)
                }
                if let hotKeyError {
                    Label(hotKeyError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Opens the clipboard history over whatever app you’re using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Pause clipboard monitoring", isOn: $settings.isMonitoringPaused)
            } footer: {
                Text("While paused, nothing new is recorded. Existing history is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.launchAtLogin) { _, newValue in
            do {
                try LaunchAtLogin.setEnabled(newValue)
                launchAtLoginNeedsApproval = LaunchAtLogin.requiresUserApproval
            } catch {
                Log.app.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
                launchAtLoginNeedsApproval = true
            }
        }
        .onAppear { launchAtLoginNeedsApproval = LaunchAtLogin.requiresUserApproval }
    }
}

// MARK: - Storage

private struct StorageSettingsTab: View {
    @Bindable var settings: SettingsStore
    let store: ClipboardStore

    @State private var storageBytes: Int?
    @State private var isConfirmingClear = false
    @State private var isCustomLimit = false
    @State private var customLimit = 30

    private let presets = [10, 30, 50, 100]

    var body: some View {
        Form {
            Section {
                Picker("History limit", selection: limitSelection) {
                    ForEach(presets, id: \.self) { Text("\($0) items").tag($0) }
                    Text("Custom…").tag(-1)
                }
                if isCustomLimit {
                    HStack {
                        Stepper(value: $customLimit, in: 1...1_000, step: 10) {
                            Text("\(customLimit) items")
                        }
                        .onChange(of: customLimit) { _, newValue in settings.historyLimit = newValue }
                    }
                }
            } footer: {
                Text("Applies to unpinned items only — pinned items are never removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Delete items automatically", selection: $settings.retentionPeriod) {
                    ForEach(RetentionPeriod.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                LabeledContent("Items stored") {
                    Text("\(store.unpinnedItems.count) recent · \(store.pinnedItems.count) pinned")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Images on disk") {
                    Text(storageBytes.map {
                        ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
                    } ?? "Calculating…")
                    .foregroundStyle(.secondary)
                }
                Button("Clear History…", role: .destructive) { isConfirmingClear = true }
            } footer: {
                Text("Everything is stored locally in ~/Library/Application Support/ClipFlow and excluded from backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) {
                store.clearHistory(keepingPinned: true)
                Task { storageBytes = await store.storageSizeOnDisk() }
            }
        } message: {
            Text("Pinned items are kept. This cannot be undone.")
        }
        .task {
            storageBytes = await store.storageSizeOnDisk()
            isCustomLimit = !presets.contains(settings.historyLimit)
            customLimit = settings.historyLimit
        }
    }

    private var limitSelection: Binding<Int> {
        Binding(
            get: { isCustomLimit ? -1 : settings.historyLimit },
            set: { newValue in
                if newValue == -1 {
                    isCustomLimit = true
                    customLimit = settings.historyLimit
                } else {
                    isCustomLimit = false
                    settings.historyLimit = newValue
                }
            }
        )
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("“System” follows the macOS appearance, including automatic switching at sunset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

private struct BehaviorSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("When copying the same thing twice", selection: $settings.duplicateHandling) {
                    ForEach(DuplicateHandling.allCases) { Text($0.displayName).tag($0) }
                }
                Text(settings.duplicateHandling.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Close window after selecting an item", isOn: $settings.closesAfterSelection)
                Toggle("Copy with a single click", isOn: $settings.copiesOnSingleClick)
                Toggle("Capture images and screenshots", isOn: $settings.capturesImages)
            }

            Section {
                Toggle("Paste automatically after selecting", isOn: $settings.pastesAutomatically)
                if settings.pastesAutomatically, !PasteWriter.hasAccessibilityPermission {
                    HStack(spacing: 8) {
                        Label("Accessibility access required", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Grant…") { PasteWriter.requestAccessibilityPermission() }
                            .controlSize(.small)
                    }
                }
            } footer: {
                Text("Without this, ClipFlow only puts the item on the clipboard and you press ⌘V yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded apps") {
                Text(settings.excludedBundleIDs.isEmpty
                     ? "No apps excluded."
                     : settings.excludedBundleIDs.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Content marked as concealed by password managers is always ignored, regardless of this list.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}
