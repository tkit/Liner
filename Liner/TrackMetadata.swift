import Foundation

protocol AudioTagStore {
    func loadMetadata(from url: URL) throws -> TrackMetadata
    func loadMetadataReport(from url: URL) -> TrackMetadataLoadReport
    func writeMetadata(_ metadata: TrackMetadata, to url: URL) throws
}

extension AudioTagStore {
    func loadMetadataReport(from url: URL) -> TrackMetadataLoadReport {
        do {
            let metadata = try loadMetadata(from: url)
            return TrackMetadataLoadReport(metadata: metadata)
        } catch TrackMetadataReadError.missingID3v2Tag {
            return TrackMetadataLoadReport(metadata: TrackMetadata())
        } catch let error as TrackMetadataReadError {
            return TrackMetadataLoadReport(metadata: TrackMetadata(), error: error)
        } catch {
            return TrackMetadataLoadReport(
                metadata: TrackMetadata(),
                error: .unreadableFile(error.localizedDescription)
            )
        }
    }
}

struct TrackMetadata: Equatable, Hashable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var track: NumberedMetadata?
    var disc: NumberedMetadata?
    var genre: String?
    var year: Int?
    var comment: String?
    var artwork: ArtworkMetadata?

    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        track: NumberedMetadata? = nil,
        disc: NumberedMetadata? = nil,
        genre: String? = nil,
        year: Int? = nil,
        comment: String? = nil,
        artwork: ArtworkMetadata? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.track = track
        self.disc = disc
        self.genre = genre
        self.year = year
        self.comment = comment
        self.artwork = artwork
    }
}

struct TrackMetadataLoadReport: Equatable, Sendable {
    var metadata: TrackMetadata
    var missingFields: Set<TrackMetadataField>
    var error: TrackMetadataReadError?

    init(
        metadata: TrackMetadata,
        missingFields: Set<TrackMetadataField>? = nil,
        error: TrackMetadataReadError? = nil
    ) {
        self.metadata = metadata
        self.missingFields = missingFields ?? metadata.missingEditableFields
        self.error = error
    }

    var hasWarnings: Bool {
        error != nil || !missingFields.isEmpty
    }
}

enum TrackMetadataReadError: Error, Equatable, Sendable {
    case missingID3v2Tag
    case unsupportedID3v2Version(Int)
    case invalidTag(String)
    case unreadableFile(String)

    var message: String {
        switch self {
        case .missingID3v2Tag:
            "No ID3v2 tag was found."
        case .unsupportedID3v2Version(let version):
            "ID3v2.\(version) is not supported yet."
        case .invalidTag(let detail):
            "The ID3v2 tag could not be parsed: \(detail)"
        case .unreadableFile(let detail):
            "The file could not be read: \(detail)"
        }
    }
}

struct NumberedMetadata: Equatable, Hashable, Sendable {
    var number: Int?
    var total: Int?

    init(number: Int? = nil, total: Int? = nil) {
        self.number = number
        self.total = total
    }
}

struct ArtworkMetadata: Equatable, Hashable, Sendable {
    var data: Data
    var mimeType: String?
    var imageDescription: String?

    init(data: Data, mimeType: String? = nil, imageDescription: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.imageDescription = imageDescription
    }
}

struct EditableTrackMetadata: Equatable, Sendable {
    let original: TrackMetadata
    private(set) var current: TrackMetadata

    init(original: TrackMetadata, current: TrackMetadata? = nil) {
        self.original = original
        self.current = current ?? original
    }

    var hasChanges: Bool {
        original != current
    }

    var dirtyFields: Set<TrackMetadataField> {
        Set(TrackMetadataField.allCases.filter { field in
            original.value(for: field) != current.value(for: field)
        })
    }

    var changes: [TrackMetadataChange] {
        TrackMetadataField.allCases.compactMap { field in
            let originalValue = original.value(for: field)
            let currentValue = current.value(for: field)

            guard originalValue != currentValue else { return nil }

            return TrackMetadataChange(
                field: field,
                originalValue: originalValue,
                currentValue: currentValue
            )
        }
    }

    mutating func update(_ field: TrackMetadataField, to value: TrackMetadataFieldValue) {
        current.setValue(value, for: field)
    }

    mutating func reset(_ field: TrackMetadataField) {
        current.setValue(original.value(for: field), for: field)
    }

    mutating func resetAll() {
        current = original
    }
}

struct TrackMetadataChange: Identifiable, Equatable, Sendable {
    var field: TrackMetadataField
    var originalValue: TrackMetadataFieldValue
    var currentValue: TrackMetadataFieldValue

    var id: TrackMetadataField { field }
}

enum TrackMetadataField: String, CaseIterable, Identifiable, Sendable {
    case title
    case artist
    case album
    case albumArtist
    case track
    case disc
    case genre
    case year
    case comment
    case artwork

    var id: Self { self }

    var title: String {
        switch self {
        case .title:
            "Title"
        case .artist:
            "Artist"
        case .album:
            "Album"
        case .albumArtist:
            "Album Artist"
        case .track:
            "Track"
        case .disc:
            "Disc"
        case .genre:
            "Genre"
        case .year:
            "Year"
        case .comment:
            "Comment"
        case .artwork:
            "Artwork"
        }
    }
}

enum TrackMetadataFieldValue: Equatable, Hashable, Sendable, CustomStringConvertible {
    case empty
    case text(String)
    case number(Int)
    case indexed(NumberedMetadata)
    case artwork(ArtworkMetadata)

    var description: String {
        switch self {
        case .empty:
            ""
        case .text(let value):
            value
        case .number(let value):
            String(value)
        case .indexed(let value):
            value.description
        case .artwork(let value):
            value.description
        }
    }
}

extension TrackMetadata {
    func value(for field: TrackMetadataField) -> TrackMetadataFieldValue {
        switch field {
        case .title:
            title.fieldValue
        case .artist:
            artist.fieldValue
        case .album:
            album.fieldValue
        case .albumArtist:
            albumArtist.fieldValue
        case .track:
            track.map(TrackMetadataFieldValue.indexed) ?? .empty
        case .disc:
            disc.map(TrackMetadataFieldValue.indexed) ?? .empty
        case .genre:
            genre.fieldValue
        case .year:
            year.map(TrackMetadataFieldValue.number) ?? .empty
        case .comment:
            comment.fieldValue
        case .artwork:
            artwork.map(TrackMetadataFieldValue.artwork) ?? .empty
        }
    }

    var missingEditableFields: Set<TrackMetadataField> {
        Set(TrackMetadataField.allCases.filter { value(for: $0) == .empty })
    }

    mutating func setValue(_ value: TrackMetadataFieldValue, for field: TrackMetadataField) {
        switch field {
        case .title:
            title = value.stringValue
        case .artist:
            artist = value.stringValue
        case .album:
            album = value.stringValue
        case .albumArtist:
            albumArtist = value.stringValue
        case .track:
            track = value.numberedValue
        case .disc:
            disc = value.numberedValue
        case .genre:
            genre = value.stringValue
        case .year:
            year = value.integerValue
        case .comment:
            comment = value.stringValue
        case .artwork:
            artwork = value.artworkValue
        }
    }
}

extension NumberedMetadata: CustomStringConvertible {
    var description: String {
        switch (number, total) {
        case (.some(let number), .some(let total)):
            "\(number)/\(total)"
        case (.some(let number), .none):
            String(number)
        case (.none, .some(let total)):
            "/\(total)"
        case (.none, .none):
            ""
        }
    }
}

extension ArtworkMetadata: CustomStringConvertible {
    var description: String {
        let format = mimeType ?? "unknown format"
        return "\(format), \(data.count) bytes"
    }
}

private extension Optional where Wrapped == String {
    var fieldValue: TrackMetadataFieldValue {
        guard let self, !self.isEmpty else { return .empty }
        return .text(self)
    }
}

private extension TrackMetadataFieldValue {
    var stringValue: String? {
        guard case .text(let value) = self, !value.isEmpty else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var numberedValue: NumberedMetadata? {
        guard case .indexed(let value) = self else { return nil }
        return value
    }

    var artworkValue: ArtworkMetadata? {
        guard case .artwork(let value) = self else { return nil }
        return value
    }
}
