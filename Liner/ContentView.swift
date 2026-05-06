import SwiftUI

struct ContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .library
    @State private var selectedTrackID: PlaceholderTrack.ID?
    @State private var searchText = ""
    @State private var isInspectorPresented = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            TrackTablePlaceholder(
                tracks: filteredTracks,
                selectedTrackID: $selectedTrackID
            )
            .inspector(isPresented: $isInspectorPresented) {
                InspectorPlaceholder(track: selectedTrack)
            }
        }
        .navigationTitle("Liner")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter tracks")
        .toolbar {
            ToolbarItemGroup {
                Button {
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Button {
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
        .frame(minWidth: 920, minHeight: 560)
    }

    private var filteredTracks: [PlaceholderTrack] {
        guard !searchText.isEmpty else { return PlaceholderTrack.samples }

        return PlaceholderTrack.samples.filter { track in
            track.fileName.localizedStandardContains(searchText)
                || track.title.localizedStandardContains(searchText)
                || track.artist.localizedStandardContains(searchText)
                || track.album.localizedStandardContains(searchText)
        }
    }

    private var selectedTrack: PlaceholderTrack? {
        PlaceholderTrack.samples.first { $0.id == selectedTrackID }
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

private struct TrackTablePlaceholder: View {
    let tracks: [PlaceholderTrack]
    @Binding var selectedTrackID: PlaceholderTrack.ID?

    var body: some View {
        VStack(spacing: 0) {
            Table(tracks, selection: $selectedTrackID) {
                TableColumn("File") { track in
                    Text(track.fileName)
                }

                TableColumn("Track") { track in
                    Text(track.trackNumber)
                        .monospacedDigit()
                }

                TableColumn("Title") { track in
                    Text(track.title)
                }

                TableColumn("Artist") { track in
                    Text(track.artist)
                }

                TableColumn("Album") { track in
                    Text(track.album)
                }

                TableColumn("Status") { track in
                    Label(track.statusTitle, systemImage: track.statusSystemImage)
                        .foregroundStyle(.secondary)
                }
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))

            TableFooterPlaceholder(trackCount: tracks.count)
        }
    }
}

private struct TableFooterPlaceholder: View {
    let trackCount: Int

    var body: some View {
        HStack {
            Label("\(trackCount) placeholder tracks", systemImage: "music.note.list")
            Spacer()
            Text("No tag reading or writing is active yet.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct InspectorPlaceholder: View {
    let track: PlaceholderTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .font(.headline)

            Divider()

            if let track {
                InspectorField(label: "File", value: track.fileName)
                InspectorField(label: "Title", value: track.title)
                InspectorField(label: "Artist", value: track.artist)
                InspectorField(label: "Album", value: track.album)
                InspectorField(label: "Track", value: track.trackNumber)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "music.note",
                    description: Text("Select a row to preview where tag details will appear.")
                )
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
    }
}

private struct InspectorField: View {
    let label: String
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

private enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case folders
    case pendingChanges

    var id: Self { self }

    var title: String {
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

private struct PlaceholderTrack: Identifiable {
    let id = UUID()
    let fileName: String
    let trackNumber: String
    let title: String
    let artist: String
    let album: String
    let statusTitle: String
    let statusSystemImage: String

    static let samples = [
        PlaceholderTrack(
            fileName: "01 - Northern Line.mp3",
            trackNumber: "01",
            title: "Northern Line",
            artist: "Sample Artist",
            album: "Draft Album",
            statusTitle: "Unloaded",
            statusSystemImage: "circle"
        ),
        PlaceholderTrack(
            fileName: "02 - Window Seat.mp3",
            trackNumber: "02",
            title: "Window Seat",
            artist: "Sample Artist",
            album: "Draft Album",
            statusTitle: "Unloaded",
            statusSystemImage: "circle"
        ),
        PlaceholderTrack(
            fileName: "03 - Last Train Home.mp3",
            trackNumber: "03",
            title: "Last Train Home",
            artist: "Sample Artist",
            album: "Draft Album",
            statusTitle: "Unloaded",
            statusSystemImage: "circle"
        )
    ]
}

#Preview {
    ContentView()
}
