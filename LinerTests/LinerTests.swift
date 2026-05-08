import XCTest
@testable import Liner

final class LinerTests: XCTestCase {
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
}
