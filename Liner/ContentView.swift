import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .library
    @State private var importedItems: [ImportedItem] = []
    @State private var selectedItemID: ImportedItem.ID?
    @State private var searchText = ""
    @State private var isInspectorPresented = true
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            ImportedItemTable(
                items: filteredItems,
                selectedItemID: $selectedItemID,
                importAction: openFileImporter
            )
            .inspector(isPresented: $isInspectorPresented) {
                InspectorPlaceholder(item: selectedItem)
            }
        }
        .navigationTitle("Liner")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter files")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openFileImporter()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
                    openFileImporter()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
            }

            ToolbarItemGroup {
                Button {
                } label: {
                    Label("Review Changes", systemImage: "list.bullet.rectangle")
                }
                .disabled(true)

                Button {
                } label: {
                    Label("Save Tags", systemImage: "square.and.arrow.down")
                }
                .disabled(true)
            }

            ToolbarItem {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.mp3, .folder],
            allowsMultipleSelection: true
        ) { result in
            handleImportedURLs(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            addImportedURLs(urls)
            return !urls.isEmpty
        }
        .frame(minWidth: 920, minHeight: 560)
    }

    private var filteredItems: [ImportedItem] {
        guard !searchText.isEmpty else { return importedItems }

        return importedItems.filter { item in
            item.displayName.localizedStandardContains(searchText)
                || item.statusTitle.localizedStandardContains(searchText)
                || item.url.path.localizedStandardContains(searchText)
        }
    }

    private var selectedItem: ImportedItem? {
        importedItems.first { $0.id == selectedItemID }
    }

    private func openFileImporter() {
        isFileImporterPresented = true
    }

    private func handleImportedURLs(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        addImportedURLs(urls)
    }

    private func addImportedURLs(_ urls: [URL]) {
        var knownURLs = Set(importedItems.map(\.url))
        let newItems = urls
            .flatMap(importableMP3URLs)
            .filter { knownURLs.insert($0).inserted }
            .map(ImportedItem.init)

        guard !newItems.isEmpty else { return }

        importedItems.append(contentsOf: newItems)
        selectedItemID = newItems.last?.id
    }

    private func importableMP3URLs(from url: URL) -> [URL] {
        let canAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if canAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let standardizedURL = url.standardizedFileURL

        if standardizedURL.isDirectory {
            return mp3Files(in: standardizedURL)
        }

        return standardizedURL.isSupportedMP3 ? [standardizedURL] : []
    }

    private func mp3Files(in folderURL: URL) -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .map(\.standardizedFileURL)
            .filter { $0.isRegularFile && $0.isSupportedMP3 }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
        .navigationTitle("Liner")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}

private struct ImportedItemTable: View {
    let items: [ImportedItem]
    @Binding var selectedItemID: ImportedItem.ID?
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Files Loaded", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Open MP3 files or folders, or drag them here from Finder.")
                } actions: {
                    Button(action: importAction) {
                        Label("Open MP3 Files or Folders", systemImage: "folder.badge.plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(items, selection: $selectedItemID) {
                    TableColumn("File") { item in
                        Label(item.displayName, systemImage: item.systemImage)
                    }

                    TableColumn("Status") { item in
                        Label(item.statusTitle, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }

            ImportedItemFooter(itemCount: items.count)
        }
    }
}

private struct ImportedItemFooter: View {
    let itemCount: Int

    var body: some View {
        HStack {
            Label("\(itemCount) MP3 files loaded", systemImage: "music.note.list")
            Spacer()
            Text("Folders are expanded to supported MP3 files.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct InspectorPlaceholder: View {
    let item: ImportedItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .font(.headline)

            Divider()

            if let item {
                InspectorField(label: "File", value: item.displayName)
                InspectorField(label: "Status", value: item.statusTitle)
                InspectorField(label: "URL", value: item.url.absoluteString)
                InspectorField(label: "Path", value: item.url.path)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc",
                    description: Text("Select a loaded URL to inspect its details.")
                )
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
    }
}

private struct InspectorField: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ImportedItem: Identifiable, Hashable {
    let url: URL

    var id: URL { url }

    let statusTitle = "Loaded"

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var systemImage: String {
        "music.note"
    }
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var isRegularFile: Bool {
        (try? resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    var isSupportedMP3: Bool {
        pathExtension.localizedCaseInsensitiveCompare("mp3") == .orderedSame
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case folders
    case pendingChanges

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .library:
            "Library"
        case .folders:
            "Folders"
        case .pendingChanges:
            "Pending Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "music.note.list"
        case .folders:
            "folder"
        case .pendingChanges:
            "square.and.pencil"
        }
    }
}

#Preview {
    ContentView()
}
