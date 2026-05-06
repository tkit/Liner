import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Library", systemImage: "music.note.list")
                Label("Pending Changes", systemImage: "square.and.pencil")
            }
            .navigationTitle("Liner")
        } detail: {
            VStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("Liner")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Drop music files here to start organizing tags.")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 640, minHeight: 420)
        }
    }
}

#Preview {
    ContentView()
}
