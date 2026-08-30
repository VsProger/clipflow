import SwiftUI

struct HistoryView: View {
    @Bindable var viewModel: ClipboardViewModel
    @Environment(SettingsStore.self) private var settings

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
            footer
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .overlay {
            if let item = viewModel.previewItem {
                PreviewOverlay(item: item, viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.transientMessage {
                ToastView(text: message)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.previewItem?.id)
        .animation(.easeOut(duration: 0.2), value: viewModel.transientMessage)
        // Фокус сразу в поиск: список уже имеет выделение, поэтому и
        // «Hotkey → Enter», и «Hotkey → набрать → Enter» работают без лишних действий.
        .onAppear { isSearchFocused = true }
        .onChange(of: viewModel.query) { viewModel.normalizeSelection() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13, weight: .medium))

            TextField("Search clipboard history", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search (⌘K)")
            }

            Menu {
                Button(settings.isMonitoringPaused ? "Resume Monitoring" : "Pause Monitoring") {
                    viewModel.toggleMonitoring()
                }
                Divider()
                Button("Clear History…") { viewModel.requestClearHistory() }
                Divider()
                Button("Settings…") { NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.pendingClearConfirmation {
            ClearConfirmationView(viewModel: viewModel)
                .frame(maxHeight: .infinity)
        } else if viewModel.isEmpty {
            EmptyStateView(shortcut: settings.hotKey.displayString)
                .frame(maxHeight: .infinity)
        } else if viewModel.hasNoResults {
            NoResultsView(query: viewModel.query)
                .frame(maxHeight: .infinity)
        } else {
            itemList
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if !viewModel.pinnedResults.isEmpty {
                        Section {
                            rows(for: viewModel.pinnedResults)
                        } header: {
                            SectionHeader(title: "Pinned", systemImage: "pin.fill")
                        }
                    }

                    if !viewModel.recentResults.isEmpty {
                        Section {
                            rows(for: viewModel.recentResults)
                        } header: {
                            if !viewModel.pinnedResults.isEmpty {
                                SectionHeader(title: "Recent", systemImage: "clock")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func rows(for items: [ClipboardItem]) -> some View {
        ForEach(items, id: \.id) { item in
            ItemRowView(
                item: item,
                viewModel: viewModel,
                isSelected: viewModel.selectedID == item.id
            )
            .id(item.id)
        }
    }
}

// MARK: - Footer

private extension HistoryView {
    var footer: some View {
        HStack(spacing: 10) {
            if settings.isMonitoringPaused {
                Label("Monitoring paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("\(viewModel.store.unpinnedItems.count) of \(settings.historyLimit)")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            KeyHintView(keys: "↩", label: "Paste")
            KeyHintView(keys: "⌘⌫", label: "Delete")
            KeyHintView(keys: "⎋", label: "Close")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.4))
    }
}

// MARK: - Supporting views

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 3)
        .background(.ultraThinMaterial)
    }
}

private struct KeyHintView: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyStateView: View {
    let shortcut: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Your clipboard history will appear here.")
                .font(.system(size: 13, weight: .medium))

            Text("Copy something to get started.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Text("Open anytime with")
                Text(shortcut)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

private struct NoResultsView: View {
    let query: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matches for “\(query)”")
                .font(.system(size: 12, weight: .medium))
            Text("Try a shorter search term.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

private struct ClearConfirmationView: View {
    let viewModel: ClipboardViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text("Clear clipboard history?")
                .font(.system(size: 13, weight: .semibold))

            Text("\(viewModel.store.unpinnedItems.count) items will be deleted. Pinned items are kept.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Cancel") { viewModel.pendingClearConfirmation = false }
                Button("Clear History") { viewModel.confirmClearHistory() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(radius: 6, y: 2)
    }
}
