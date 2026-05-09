import Foundation

struct ID3v2AudioTagStore: AudioTagStore {
    func loadMetadata(from url: URL) throws -> TrackMetadata {
        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TrackMetadataReadError.unreadableFile(error.localizedDescription)
        }

        return try ID3v2MetadataParser(data: data).parse()
    }

    func loadMetadataReport(from url: URL) -> TrackMetadataLoadReport {
        do {
            let metadata = try loadMetadata(from: url)
            return TrackMetadataLoadReport(metadata: metadata)
        } catch let error as TrackMetadataReadError {
            return TrackMetadataLoadReport(metadata: TrackMetadata(), error: error)
        } catch {
            return TrackMetadataLoadReport(
                metadata: TrackMetadata(),
                error: .unreadableFile(error.localizedDescription)
            )
        }
    }

    func writeMetadata(_ metadata: TrackMetadata, to url: URL) throws {
        _ = metadata
        _ = url
        throw TrackMetadataReadError.invalidTag("ID3v2 writing is not implemented yet.")
    }
}

private struct ID3v2MetadataParser {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> TrackMetadata {
        guard data.count >= 10 else {
            throw TrackMetadataReadError.missingID3v2Tag
        }

        let bytes = [UInt8](data.prefix(10))
        guard bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            throw TrackMetadataReadError.missingID3v2Tag
        }

        let majorVersion = Int(bytes[3])
        guard majorVersion == 3 || majorVersion == 4 else {
            throw TrackMetadataReadError.unsupportedID3v2Version(majorVersion)
        }

        let tagSize = try syncSafeInteger(bytes[6...9])
        guard tagSize >= 0, data.count >= 10 + tagSize else {
            throw TrackMetadataReadError.invalidTag("Declared tag size exceeds file length.")
        }

        let flags = bytes[5]
        let tagEnd = 10 + tagSize
        var cursor = 10

        if flags & 0x40 != 0 {
            cursor = try skipExtendedHeader(majorVersion: majorVersion, cursor: cursor, tagEnd: tagEnd)
        }

        var frames: [String: Data] = [:]
        while cursor + 10 <= tagEnd {
            let header = data[cursor..<(cursor + 10)]
            let frameIDData = header.prefix(4)

            guard !frameIDData.allSatisfy({ $0 == 0 }) else { break }

            let frameID = String(decoding: frameIDData, as: UTF8.self)
            guard frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else { break }

            let sizeBytes = Array(header.dropFirst(4).prefix(4))
            let frameSize = majorVersion == 4
                ? try syncSafeInteger(sizeBytes[0...3])
                : bigEndianInteger(sizeBytes[0...3])

            guard frameSize >= 0, cursor + 10 + frameSize <= tagEnd else {
                throw TrackMetadataReadError.invalidTag("Frame \(frameID) exceeds tag bounds.")
            }

            if frameSize > 0 {
                frames[frameID] = data[(cursor + 10)..<(cursor + 10 + frameSize)]
            }

            cursor += 10 + frameSize
        }

        return TrackMetadata(
            title: textValue(from: frames["TIT2"]),
            artist: textValue(from: frames["TPE1"]),
            album: textValue(from: frames["TALB"]),
            albumArtist: textValue(from: frames["TPE2"]),
            track: numberedValue(from: frames["TRCK"]),
            disc: numberedValue(from: frames["TPOS"]),
            genre: textValue(from: frames["TCON"]),
            year: yearValue(from: frames["TDRC"]) ?? yearValue(from: frames["TYER"]),
            comment: commentValue(from: frames["COMM"]) ?? userTextValue(named: "comment", from: frames["TXXX"]),
            artwork: artworkValue(from: frames["APIC"])
        )
    }

    private func skipExtendedHeader(majorVersion: Int, cursor: Int, tagEnd: Int) throws -> Int {
        guard cursor + 4 <= tagEnd else {
            throw TrackMetadataReadError.invalidTag("Extended header is truncated.")
        }

        let sizeBytes = Array(data[cursor..<(cursor + 4)])
        let payloadSize = majorVersion == 4
            ? try syncSafeInteger(sizeBytes[0...3])
            : bigEndianInteger(sizeBytes[0...3])
        let extendedHeaderSize = majorVersion == 4 ? payloadSize : payloadSize + 4

        guard extendedHeaderSize >= 4, cursor + extendedHeaderSize <= tagEnd else {
            throw TrackMetadataReadError.invalidTag("Extended header exceeds tag bounds.")
        }

        return cursor + extendedHeaderSize
    }

    private func textValue(from frameData: Data?) -> String? {
        guard let frameData, let encoding = frameData.first else { return nil }
        return decodeText(frameData.dropFirst(), encoding: encoding)
    }

    private func numberedValue(from frameData: Data?) -> NumberedMetadata? {
        guard let text = textValue(from: frameData) else { return nil }
        let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let total = parts.dropFirst().first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard number != nil || total != nil else { return nil }
        return NumberedMetadata(number: number, total: total)
    }

    private func yearValue(from frameData: Data?) -> Int? {
        guard let text = textValue(from: frameData) else { return nil }
        let prefix = text.prefix(4)
        return prefix.count == 4 ? Int(prefix) : nil
    }

    private func commentValue(from frameData: Data?) -> String? {
        guard let frameData, let encoding = frameData.first, frameData.count > 4 else { return nil }
        let payload = frameData.dropFirst(4)
        let textStart = textTerminatorEnd(in: payload, encoding: encoding) ?? payload.startIndex
        return decodeText(
            payload[textStart...],
            encoding: encoding,
            fallbackUTF16Encoding: utf16Encoding(from: payload[..<textStart])
        )
    }

    private func userTextValue(named name: String, from frameData: Data?) -> String? {
        guard let frameData, let encoding = frameData.first else { return nil }
        let payload = frameData.dropFirst()
        guard let valueStart = textTerminatorEnd(in: payload, encoding: encoding) else { return nil }
        let description = decodeText(payload[..<valueStart], encoding: encoding)

        guard description?.localizedCaseInsensitiveCompare(name) == .orderedSame else {
            return nil
        }

        return decodeText(
            payload[valueStart...],
            encoding: encoding,
            fallbackUTF16Encoding: utf16Encoding(from: payload[..<valueStart])
        )
    }

    private func artworkValue(from frameData: Data?) -> ArtworkMetadata? {
        guard let frameData, let encoding = frameData.first else { return nil }
        var cursor = frameData.index(after: frameData.startIndex)

        guard let mimeEnd = frameData[cursor...].firstIndex(of: 0) else { return nil }
        let mimeType = String(data: frameData[cursor..<mimeEnd], encoding: .isoLatin1)
        cursor = frameData.index(after: mimeEnd)

        guard cursor < frameData.endIndex else { return nil }
        cursor = frameData.index(after: cursor)

        guard cursor < frameData.endIndex else { return nil }
        let descriptionPayload = frameData[cursor...]
        guard let artworkStart = textTerminatorEnd(in: descriptionPayload, encoding: encoding) else {
            return nil
        }

        let imageDescription = decodeText(descriptionPayload[..<artworkStart], encoding: encoding)
        let artworkData = Data(frameData[artworkStart...])
        guard !artworkData.isEmpty else { return nil }

        return ArtworkMetadata(
            data: artworkData,
            mimeType: mimeType?.nilIfEmpty,
            imageDescription: imageDescription
        )
    }

    private func decodeText(
        _ bytes: Data.SubSequence,
        encoding: UInt8,
        fallbackUTF16Encoding: String.Encoding? = nil
    ) -> String? {
        let data = Data(bytes)
        let decoded: String?

        switch encoding {
        case 0:
            decoded = String(data: data, encoding: .isoLatin1)
        case 1:
            decoded = String(data: data, encoding: .utf16)
                ?? fallbackUTF16Encoding.flatMap { String(data: data, encoding: $0) }
                ?? String(data: data, encoding: .utf16LittleEndian)
        case 2:
            decoded = String(data: data, encoding: .utf16BigEndian)
        case 3:
            decoded = String(data: data, encoding: .utf8)
        default:
            decoded = String(data: data, encoding: .utf8)
        }

        return decoded?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            .nilIfEmpty
    }

    private func utf16Encoding(from bytes: Data.SubSequence) -> String.Encoding? {
        guard bytes.count >= 2 else { return nil }

        let first = bytes[bytes.startIndex]
        let second = bytes[bytes.index(after: bytes.startIndex)]

        switch (first, second) {
        case (0xFE, 0xFF):
            return .utf16BigEndian
        case (0xFF, 0xFE):
            return .utf16LittleEndian
        default:
            return nil
        }
    }

    private func textTerminatorEnd(in bytes: Data.SubSequence, encoding: UInt8) -> Data.Index? {
        let terminatorLength = encoding == 1 || encoding == 2 ? 2 : 1
        var cursor = bytes.startIndex

        while cursor < bytes.endIndex {
            if terminatorLength == 1, bytes[cursor] == 0 {
                return bytes.index(after: cursor)
            }

            if terminatorLength == 2,
               bytes.index(after: cursor) < bytes.endIndex,
               bytes[cursor] == 0,
               bytes[bytes.index(after: cursor)] == 0 {
                return bytes.index(cursor, offsetBy: 2)
            }

            cursor = bytes.index(cursor, offsetBy: terminatorLength, limitedBy: bytes.endIndex) ?? bytes.endIndex
        }

        return nil
    }

    private func syncSafeInteger(_ bytes: ArraySlice<UInt8>) throws -> Int {
        guard bytes.count == 4, bytes.allSatisfy({ $0 & 0x80 == 0 }) else {
            throw TrackMetadataReadError.invalidTag("Invalid syncsafe integer.")
        }

        return bytes.reduce(0) { ($0 << 7) | Int($1) }
    }

    private func bigEndianInteger(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
