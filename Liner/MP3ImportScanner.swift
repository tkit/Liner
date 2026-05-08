import Foundation

struct MP3ImportScanner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(urls: [URL], existingURLs: Set<URL> = []) -> MP3ImportScanResult {
        var acceptedURLs: [URL] = []
        var skippedItems: [MP3ImportSkippedItem] = []
        var knownURLs = Set(existingURLs.map(\.standardizedFileURL))

        for url in urls {
            let canAccessScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if canAccessScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            scan(
                url: url.standardizedFileURL,
                knownURLs: &knownURLs,
                acceptedURLs: &acceptedURLs,
                skippedItems: &skippedItems
            )
        }

        return MP3ImportScanResult(
            acceptedURLs: acceptedURLs,
            skippedItems: skippedItems
        )
    }

    private func scan(
        url: URL,
        knownURLs: inout Set<URL>,
        acceptedURLs: inout [URL],
        skippedItems: inout [MP3ImportSkippedItem]
    ) {
        switch resourceKind(for: url) {
        case .directory:
            scanFolder(
                url,
                knownURLs: &knownURLs,
                acceptedURLs: &acceptedURLs,
                skippedItems: &skippedItems
            )
        case .regularFile:
            scanFile(
                url,
                knownURLs: &knownURLs,
                acceptedURLs: &acceptedURLs,
                skippedItems: &skippedItems
            )
        case .other:
            skippedItems.append(MP3ImportSkippedItem(url: url, reason: .unsupportedFile))
        case .unreadable:
            skippedItems.append(MP3ImportSkippedItem(url: url, reason: .readError))
        }
    }

    private func scanFolder(
        _ folderURL: URL,
        knownURLs: inout Set<URL>,
        acceptedURLs: inout [URL],
        skippedItems: inout [MP3ImportSkippedItem]
    ) {
        var enumerationErrors: [MP3ImportSkippedItem] = []
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: options,
            errorHandler: { url, _ in
                enumerationErrors.append(
                    MP3ImportSkippedItem(url: url.standardizedFileURL, reason: .readError)
                )
                return true
            }
        ) else {
            skippedItems.append(MP3ImportSkippedItem(url: folderURL, reason: .readError))
            return
        }

        let folderItems = enumerator
            .compactMap { $0 as? URL }
            .map(\.standardizedFileURL)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        for itemURL in folderItems {
            switch resourceKind(for: itemURL) {
            case .directory:
                continue
            case .regularFile:
                scanFile(
                    itemURL,
                    knownURLs: &knownURLs,
                    acceptedURLs: &acceptedURLs,
                    skippedItems: &skippedItems
                )
            case .other:
                skippedItems.append(MP3ImportSkippedItem(url: itemURL, reason: .unsupportedFile))
            case .unreadable:
                skippedItems.append(MP3ImportSkippedItem(url: itemURL, reason: .readError))
            }
        }

        skippedItems.append(contentsOf: enumerationErrors)
    }

    private func scanFile(
        _ fileURL: URL,
        knownURLs: inout Set<URL>,
        acceptedURLs: inout [URL],
        skippedItems: inout [MP3ImportSkippedItem]
    ) {
        guard fileURL.isSupportedMP3 else {
            skippedItems.append(MP3ImportSkippedItem(url: fileURL, reason: .unsupportedFile))
            return
        }

        guard knownURLs.insert(fileURL).inserted else {
            skippedItems.append(MP3ImportSkippedItem(url: fileURL, reason: .duplicate))
            return
        }

        acceptedURLs.append(fileURL)
    }

    private func resourceKind(for url: URL) -> ResourceKind {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values.isDirectory == true {
                return .directory
            }

            if values.isRegularFile == true {
                return .regularFile
            }

            return .other
        } catch {
            return .unreadable
        }
    }
}

struct MP3ImportScanResult: Equatable {
    let acceptedURLs: [URL]
    let skippedItems: [MP3ImportSkippedItem]
}

struct MP3ImportSkippedItem: Identifiable, Hashable {
    let url: URL
    let reason: MP3ImportSkipReason

    var id: String {
        "\(url.path)|\(reason.rawValue)"
    }

    var displayName: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}

enum MP3ImportSkipReason: String, Hashable {
    case duplicate
    case readError
    case unsupportedFile

    var title: String {
        switch self {
        case .duplicate:
            "Duplicate"
        case .readError:
            "Could Not Read"
        case .unsupportedFile:
            "Unsupported File"
        }
    }
}

private enum ResourceKind {
    case directory
    case regularFile
    case other
    case unreadable
}

private extension URL {
    var isSupportedMP3: Bool {
        pathExtension.localizedCaseInsensitiveCompare("mp3") == .orderedSame
    }
}
