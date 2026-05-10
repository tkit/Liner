import XCTest
@testable import Liner

final class LinerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }

        temporaryDirectories = []
        try super.tearDownWithError()
    }

    func testEditableMetadataStartsClean() {
        let metadata = TrackMetadata(
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumArtist: "Album Artist",
            track: NumberedMetadata(number: 1, total: 10),
            disc: NumberedMetadata(number: 1, total: 2),
            genre: "Rock",
            year: 2026,
            comment: "Draft",
            artwork: ArtworkMetadata(data: Data([0x01, 0x02]), mimeType: "image/jpeg")
        )

        let state = EditableTrackMetadata(original: metadata)

        XCTAssertEqual(state.current, metadata)
        XCTAssertFalse(state.hasChanges)
        XCTAssertTrue(state.dirtyFields.isEmpty)
        XCTAssertTrue(state.changes.isEmpty)
    }

    func testEditableMetadataTracksChangedFields() {
        let original = TrackMetadata(
            title: "Original",
            artist: "Artist",
            track: NumberedMetadata(number: 1, total: 10)
        )
        var state = EditableTrackMetadata(original: original)

        state.update(.title, to: .text("Edited"))
        state.update(.track, to: .indexed(NumberedMetadata(number: 2, total: 10)))

        XCTAssertTrue(state.hasChanges)
        XCTAssertEqual(state.dirtyFields, [.title, .track])
        XCTAssertEqual(
            state.changes,
            [
                TrackMetadataChange(
                    field: .title,
                    originalValue: .text("Original"),
                    currentValue: .text("Edited")
                ),
                TrackMetadataChange(
                    field: .track,
                    originalValue: .indexed(NumberedMetadata(number: 1, total: 10)),
                    currentValue: .indexed(NumberedMetadata(number: 2, total: 10))
                )
            ]
        )
    }

    func testEditableMetadataCanResetFieldAndAllChanges() {
        var state = EditableTrackMetadata(
            original: TrackMetadata(title: "Original", artist: "Artist")
        )

        state.update(.title, to: .text("Edited"))
        state.update(.artist, to: .empty)

        state.reset(.title)

        XCTAssertEqual(state.current.title, "Original")
        XCTAssertEqual(state.current.artist, nil)
        XCTAssertEqual(state.dirtyFields, [.artist])

        state.resetAll()

        XCTAssertEqual(state.current, state.original)
        XCTAssertFalse(state.hasChanges)
    }

    func testTrackMetadataFieldParsesEditedCellValues() {
        XCTAssertEqual(TrackMetadataField.title.editedValue(from: " Edited Title "), .text("Edited Title"))
        XCTAssertEqual(TrackMetadataField.comment.editedValue(from: ""), .empty)
        XCTAssertEqual(TrackMetadataField.year.editedValue(from: "2026"), .number(2026))
        XCTAssertEqual(TrackMetadataField.year.editedValue(from: "not a year"), .empty)
        XCTAssertEqual(
            TrackMetadataField.track.editedValue(from: "2/12"),
            .indexed(NumberedMetadata(number: 2, total: 12))
        )
        XCTAssertEqual(
            TrackMetadataField.disc.editedValue(from: "/2"),
            .indexed(NumberedMetadata(number: nil, total: 2))
        )
    }

    func testSpreadsheetClipboardParsesTSVRows() {
        XCTAssertEqual(
            SpreadsheetClipboard.rows(from: "Title\tArtist\nSecond\tOther Artist\n"),
            [
                ["Title", "Artist"],
                ["Second", "Other Artist"]
            ]
        )
    }

    func testSpreadsheetClipboardPreservesEmptyCells() {
        XCTAssertEqual(
            SpreadsheetClipboard.rows(from: "Title\t\tAlbum\n\tArtist\t"),
            [
                ["Title", "", "Album"],
                ["", "Artist", ""]
            ]
        )
    }

    func testSpreadsheetClipboardCreatesTSVFromRows() {
        XCTAssertEqual(
            SpreadsheetClipboard.tsv(from: [
                ["Track 01.mp3", "Track 02.mp3"],
                ["Loaded", "Modified"]
            ]),
            "Track 01.mp3\tTrack 02.mp3\nLoaded\tModified"
        )
    }

    func testMetadataCellRangeReturnsRectangularCellsInRowMajorOrder() {
        let range = MetadataCellRange(
            anchor: MetadataCell(row: 3, column: 4),
            focused: MetadataCell(row: 1, column: 2)
        )

        XCTAssertEqual(range.topLeft, MetadataCell(row: 1, column: 2))
        XCTAssertEqual(range.bottomRight, MetadataCell(row: 3, column: 4))
        XCTAssertTrue(range.contains(MetadataCell(row: 2, column: 3)))
        XCTAssertFalse(range.contains(MetadataCell(row: 4, column: 3)))
        XCTAssertEqual(
            range.cells,
            [
                MetadataCell(row: 1, column: 2),
                MetadataCell(row: 1, column: 3),
                MetadataCell(row: 1, column: 4),
                MetadataCell(row: 2, column: 2),
                MetadataCell(row: 2, column: 3),
                MetadataCell(row: 2, column: 4),
                MetadataCell(row: 3, column: 2),
                MetadataCell(row: 3, column: 3),
                MetadataCell(row: 3, column: 4)
            ]
        )
    }

    func testSpreadsheetClipboardExpandsSingleValueAcrossSelectedRange() {
        let selectedRange = MetadataCellRange(
            anchor: MetadataCell(row: 0, column: 2),
            focused: MetadataCell(row: 2, column: 2)
        )

        XCTAssertEqual(
            SpreadsheetClipboard.pasteTargets(
                for: [["Album Name"]],
                startCell: MetadataCell(row: 0, column: 2),
                selectedRange: selectedRange
            ),
            [
                SpreadsheetPasteTarget(cell: MetadataCell(row: 0, column: 2), value: "Album Name"),
                SpreadsheetPasteTarget(cell: MetadataCell(row: 1, column: 2), value: "Album Name"),
                SpreadsheetPasteTarget(cell: MetadataCell(row: 2, column: 2), value: "Album Name")
            ]
        )
    }

    func testSpreadsheetClipboardExpandsCopiedColumnFromSingleStartCell() {
        XCTAssertEqual(
            SpreadsheetClipboard.pasteTargets(
                for: [["01 Intro.mp3"], ["02 Main.mp3"], ["03 Outro.mp3"]],
                startCell: MetadataCell(row: 4, column: 2),
                selectedRange: nil
            ),
            [
                SpreadsheetPasteTarget(cell: MetadataCell(row: 4, column: 2), value: "01 Intro.mp3"),
                SpreadsheetPasteTarget(cell: MetadataCell(row: 5, column: 2), value: "02 Main.mp3"),
                SpreadsheetPasteTarget(cell: MetadataCell(row: 6, column: 2), value: "03 Outro.mp3")
            ]
        )
    }

    func testID3v2AudioTagStoreLoadsBasicFixtureMetadata() throws {
        let metadata = try ID3v2AudioTagStore().loadMetadata(from: fixtureURL(named: "liner-id3v23-basic.mp3"))

        XCTAssertEqual(metadata.title, "Fixture Tone")
        XCTAssertEqual(metadata.artist, "Liner Tests")
        XCTAssertEqual(metadata.album, "Liner Fixture Album")
        XCTAssertEqual(metadata.albumArtist, "Liner Tests")
        XCTAssertEqual(metadata.track, NumberedMetadata(number: 1, total: 1))
        XCTAssertEqual(metadata.disc, NumberedMetadata(number: 1, total: 1))
        XCTAssertEqual(metadata.genre, "Test")
        XCTAssertEqual(metadata.year, 2026)
        XCTAssertEqual(metadata.comment, "Generated by scripts/generate-audio-fixtures.sh")
    }

    func testID3v2AudioTagStoreLoadsJapaneseFixtureMetadata() throws {
        let metadata = try ID3v2AudioTagStore().loadMetadata(from: fixtureURL(named: "liner-id3v23-japanese.mp3"))

        XCTAssertEqual(metadata.title, "夜明けのテスト")
        XCTAssertEqual(metadata.artist, "ライナー")
        XCTAssertEqual(metadata.album, "日本語フィクスチャ")
        XCTAssertEqual(metadata.albumArtist, "テスト集団")
        XCTAssertEqual(metadata.track, NumberedMetadata(number: 2, total: 12))
        XCTAssertEqual(metadata.disc, NumberedMetadata(number: 1, total: 2))
        XCTAssertEqual(metadata.genre, "電子音楽")
        XCTAssertEqual(metadata.year, 2026)
        XCTAssertEqual(metadata.comment, "コメント本文")
    }

    func testID3v2AudioTagStoreLoadsEmptyTagFixtureAsMissingFields() throws {
        let report = ID3v2AudioTagStore().loadMetadataReport(
            from: fixtureURL(named: "liner-id3v23-empty-tags.mp3")
        )

        XCTAssertEqual(report.metadata, TrackMetadata())
        XCTAssertNil(report.error)
        XCTAssertEqual(report.missingFields, Set(TrackMetadataField.allCases))
    }

    func testID3v2AudioTagStoreReportsMissingFields() {
        let report = ID3v2AudioTagStore().loadMetadataReport(
            from: fixtureURL(named: "liner-id3v23-basic.mp3")
        )

        XCTAssertNil(report.error)
        XCTAssertEqual(report.missingFields, [.artwork])
    }

    func testID3v2AudioTagStoreTreatsMissingID3v2TagAsEditableEmptyMetadata() throws {
        let folderURL = try makeTemporaryDirectory()
        let fileURL = folderURL.appendingPathComponent("empty.mp3")
        try Data().write(to: fileURL)

        let report = ID3v2AudioTagStore().loadMetadataReport(from: fileURL)

        XCTAssertEqual(report.metadata, TrackMetadata())
        XCTAssertNil(report.error)
        XCTAssertEqual(report.missingFields, Set(TrackMetadataField.allCases))
    }

    func testID3v2AudioTagStoreReportsInvalidFixtureTagSize() {
        let report = ID3v2AudioTagStore().loadMetadataReport(
            from: fixtureURL(named: "liner-id3v23-corrupt-size.mp3")
        )

        XCTAssertEqual(report.metadata, TrackMetadata())
        XCTAssertEqual(report.error, .invalidTag("Declared tag size exceeds file length."))
        XCTAssertEqual(report.missingFields, Set(TrackMetadataField.allCases))
    }

    func testMP3ImportScannerDetectsOnlyMP3FilesInFolder() throws {
        let folderURL = try makeTemporaryDirectory()
        let nestedFolderURL = folderURL.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: nestedFolderURL, withIntermediateDirectories: true)
        let firstMP3URL = folderURL.appendingPathComponent("01 Intro.mp3")
        let secondMP3URL = nestedFolderURL.appendingPathComponent("02 Song.MP3")
        let textURL = folderURL.appendingPathComponent("notes.txt")
        try Data().write(to: firstMP3URL)
        try Data().write(to: secondMP3URL)
        try Data().write(to: textURL)

        let result = MP3ImportScanner().scan(urls: [folderURL])

        XCTAssertEqual(
            result.acceptedURLs,
            [firstMP3URL, secondMP3URL].map(\.standardizedFileURL)
        )
        XCTAssertEqual(
            result.skippedItems,
            [
                MP3ImportSkippedItem(
                    url: textURL.standardizedFileURL,
                    reason: .unsupportedFile
                )
            ]
        )
    }

    func testMP3ImportScannerReportsDuplicatesAndUnsupportedFiles() throws {
        let folderURL = try makeTemporaryDirectory()
        let mp3URL = folderURL.appendingPathComponent("song.mp3")
        let aacURL = folderURL.appendingPathComponent("song.m4a")
        try Data().write(to: mp3URL)
        try Data().write(to: aacURL)

        let result = MP3ImportScanner().scan(
            urls: [mp3URL, mp3URL, aacURL],
            existingURLs: [mp3URL.standardizedFileURL]
        )

        XCTAssertTrue(result.acceptedURLs.isEmpty)
        XCTAssertEqual(
            result.skippedItems,
            [
                MP3ImportSkippedItem(url: mp3URL.standardizedFileURL, reason: .duplicate),
                MP3ImportSkippedItem(url: mp3URL.standardizedFileURL, reason: .duplicate),
                MP3ImportSkippedItem(url: aacURL.standardizedFileURL, reason: .unsupportedFile)
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func fixtureURL(named fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/Audio")
            .appendingPathComponent(fileName)
    }
}
