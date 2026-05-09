import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private let tagStore = ID3v2AudioTagStore()

    @State private var selectedSidebarItem: SidebarItem? = .library
    @State private var importedItems: [ImportedItem] = []
    @State private var selectedItemID: ImportedItem.ID?
    @State private var searchText = ""
    @State private var isInspectorPresented = true
    @State private var isFileImporterPresented = false
    @State private var lastImportSkippedItems: [MP3ImportSkippedItem] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            ImportedItemTable(
                items: filteredItems,
                skippedItems: lastImportSkippedItems,
                selectedItemID: $selectedItemID,
                importAction: openFileImporter,
                dismissSkippedItemsAction: { lastImportSkippedItems = [] }
            )
            .inspector(isPresented: $isInspectorPresented) {
                InspectorPlaceholder(item: selectedItem)
            }
        }
        .navigationTitle("")
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
        .frame(minWidth: 700, minHeight: 360)
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
        let scanResult = MP3ImportScanner().scan(
            urls: urls,
            existingURLs: Set(importedItems.map(\.url))
        )
        let newItems = scanResult.acceptedURLs.map { url in
            ImportedItem(url: url, metadataLoadReport: loadMetadataReport(from: url))
        }

        lastImportSkippedItems = scanResult.skippedItems

        guard !newItems.isEmpty else { return }

        importedItems.append(contentsOf: newItems)
        selectedItemID = newItems.last?.id
    }

    private func loadMetadataReport(from url: URL) -> TrackMetadataLoadReport {
        let canAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if canAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return tagStore.loadMetadataReport(from: url)
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
        .navigationSplitViewColumnWidth(min: 150, ideal: 210, max: 260)
    }
}

private struct ImportedItemTable: View {
    let items: [ImportedItem]
    let skippedItems: [MP3ImportSkippedItem]
    @Binding var selectedItemID: ImportedItem.ID?
    let importAction: () -> Void
    let dismissSkippedItemsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !skippedItems.isEmpty {
                ImportSkippedBanner(
                    skippedItems: skippedItems,
                    dismissAction: dismissSkippedItemsAction
                )
            }

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
                        Label(item.statusTitle, systemImage: item.statusSystemImage)
                            .foregroundStyle(item.statusStyle)
                    }
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }

            ImportedItemFooter(itemCount: items.count)
        }
    }
}

private struct ImportSkippedBanner: View {
    let skippedItems: [MP3ImportSkippedItem]
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(skippedItems.count) files skipped")
                    .font(.callout.weight(.semibold))
                Text("Review skipped files before continuing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(skippedItems) { item in
                    Text(verbatim: "\(item.displayName): ")
                        + Text(LocalizedStringKey(item.reason.title))
                }
            } label: {
                Label("Details", systemImage: "list.bullet")
            }
            .menuStyle(.button)
            .fixedSize()

            Button(action: dismissAction) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ImportedItemFooter: View {
    let itemCount: Int

    var body: some View {
        HStack {
            Label("\(itemCount) MP3 files loaded", systemImage: "music.note.list")
                .lineLimit(1)
            Spacer()
            Text("Folders are expanded to supported MP3 files.")
                .lineLimit(1)
                .truncationMode(.tail)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Inspector", systemImage: "sidebar.trailing")
                    .font(.headline)

                Divider()

                if let item {
                    InspectorField(label: "File", value: item.displayName)
                    InspectorField(label: "Status", value: item.statusTitle)
                    if let errorMessage = item.metadataLoadReport.error?.message {
                        InspectorField(label: "Read Error", value: errorMessage)
                    }
                    if !item.metadataLoadReport.missingFields.isEmpty {
                        InspectorField(label: "Missing Tags", value: item.missingFieldsSummary)
                    }
                    InspectorField(label: "Title", value: item.metadataState.current.title ?? "")
                    InspectorField(label: "Artist", value: item.metadataState.current.artist ?? "")
                    InspectorField(label: "Album", value: item.metadataState.current.album ?? "")
                    InspectorField(label: "Album Artist", value: item.metadataState.current.albumArtist ?? "")
                    InspectorField(label: "Track", value: item.metadataState.current.track?.description ?? "")
                    InspectorField(label: "Disc", value: item.metadataState.current.disc?.description ?? "")
                    InspectorField(label: "Genre", value: item.metadataState.current.genre ?? "")
                    InspectorField(label: "Year", value: item.metadataState.current.year.map(String.init) ?? "")
                    InspectorField(label: "Comment", value: item.metadataState.current.comment ?? "")
                    InspectorField(label: "Artwork", value: item.metadataState.current.artwork?.description ?? "")
                    InspectorField(label: "URL", value: item.url.absoluteString)
                    InspectorField(label: "Path", value: item.url.path)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "doc",
                        description: Text("Select a loaded URL to inspect its details.")
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
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
    var metadataLoadReport: TrackMetadataLoadReport
    var metadataState: EditableTrackMetadata

    var id: URL { url }

    static func == (lhs: ImportedItem, rhs: ImportedItem) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    init(url: URL, metadataLoadReport: TrackMetadataLoadReport = TrackMetadataLoadReport(metadata: TrackMetadata())) {
        self.url = url
        self.metadataLoadReport = metadataLoadReport
        self.metadataState = EditableTrackMetadata(original: metadataLoadReport.metadata)
    }

    var statusTitle: String {
        if metadataLoadReport.error != nil {
            return "Read Error"
        }

        if !metadataLoadReport.missingFields.isEmpty {
            return "Missing Tags"
        }

        return metadataState.hasChanges ? "Modified" : "Loaded"
    }

    var statusSystemImage: String {
        if metadataLoadReport.error != nil {
            return "exclamationmark.triangle"
        }

        if !metadataLoadReport.missingFields.isEmpty {
            return "info.circle"
        }

        return metadataState.hasChanges ? "pencil.circle" : "checkmark.circle"
    }

    var statusStyle: AnyShapeStyle {
        if metadataLoadReport.error != nil {
            return AnyShapeStyle(.red)
        }

        if !metadataLoadReport.missingFields.isEmpty {
            return AnyShapeStyle(.yellow)
        }

        return AnyShapeStyle(.secondary)
    }

    var missingFieldsSummary: String {
        metadataLoadReport.missingFields
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: ", ")
    }

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var systemImage: String {
        "music.note"
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
