import XCTest
@testable import ThreeMFKit

/// Exercises `ZipArchive`'s branches that the higher-level 3MF fixtures in
/// `ThreeMFFixtureFactory` don't reach: malformed/corrupt archive shapes,
/// the case-insensitive lookup fallback, `entryPaths`/`entries(matching:)`,
/// zero-byte entries, and a genuine ZIP64 EOCD + locator (as opposed to the
/// per-entry ZIP64 extra field already covered by `LoaderTests`).
final class ZipArchiveTests: XCTestCase {

    // MARK: - Hand-rolled archive builder
    //
    // These tests need byte-level control over specific fields that
    // `ZipWriter` doesn't expose (bogus signatures/offsets/lengths), so they
    // build minimal STORE-only archives directly.

    private func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    private func le64(_ v: UInt64) -> Data {
        le32(UInt32(v & 0xFFFF_FFFF)) + le32(UInt32(v >> 32))
    }

    /// Builds a single-entry STORE archive and returns both the full archive
    /// bytes and the byte offset at which its central-directory record
    /// begins (fields within it are documented in `ZipArchive`).
    private func buildSingleEntryArchive(path: String = "file.txt", content: Data = Data("hello".utf8)) -> (data: Data, centralDirOffset: Int) {
        let nameData = Data(path.utf8)
        let crc = CRC32.checksum(content)

        var local = Data()
        local += le32(0x0403_4b50)
        local += le16(20) // version needed
        local += le16(0) // flags
        local += le16(0) // method: store
        local += le16(0) // mod time
        local += le16(0) // mod date
        local += le32(crc)
        local += le32(UInt32(content.count)) // compressed size
        local += le32(UInt32(content.count)) // uncompressed size
        local += le16(UInt16(nameData.count))
        local += le16(0) // extra len
        local += nameData
        local += content

        let centralDirOffset = local.count
        var central = Data()
        central += le32(0x0201_4b50)
        central += le16(20) // version made by
        central += le16(20) // version needed
        central += le16(0) // flags
        central += le16(0) // method: store
        central += le16(0) // mod time
        central += le16(0) // mod date
        central += le32(crc)
        central += le32(UInt32(content.count)) // compressed size
        central += le32(UInt32(content.count)) // uncompressed size
        central += le16(UInt16(nameData.count))
        central += le16(0) // extra len
        central += le16(0) // comment len
        central += le16(0) // disk start
        central += le16(0) // internal attrs
        central += le32(0) // external attrs
        central += le32(0) // local header offset
        central += nameData

        let centralDirSize = central.count

        var eocd = Data()
        eocd += le32(0x0605_4b50)
        eocd += le16(0) // disk num
        eocd += le16(0) // disk with cd
        eocd += le16(1) // entries this disk
        eocd += le16(1) // total entries
        eocd += le32(UInt32(centralDirSize))
        eocd += le32(UInt32(centralDirOffset))
        eocd += le16(0) // comment len

        return (local + central + eocd, centralDirOffset)
    }

    // MARK: - Happy-path accessors not exercised by the higher-level fixtures

    func testEntryPathsAndEntriesMatching() throws {
        let (data, _) = buildSingleEntryArchive(path: "Metadata/foo.txt")
        let zip = try ZipArchive(data: data)
        XCTAssertEqual(zip.entryPaths, ["Metadata/foo.txt"])
        XCTAssertEqual(zip.entries(matching: { $0.hasSuffix(".txt") }), ["Metadata/foo.txt"])
        XCTAssertEqual(zip.entries(matching: { $0.hasSuffix(".png") }), [])
    }

    func testDataCaseInsensitiveFallsBackWhenExactCaseMisses() throws {
        let (data, _) = buildSingleEntryArchive(path: "Metadata/Thumbnail.PNG", content: Data("png-bytes".utf8))
        let zip = try ZipArchive(data: data)
        XCTAssertNil(try zip.data(for: "metadata/thumbnail.png"))
        XCTAssertEqual(try zip.dataCaseInsensitive(for: "metadata/thumbnail.png"), Data("png-bytes".utf8))
    }

    func testDataCaseInsensitivePrefersExactCaseMatch() throws {
        let (data, _) = buildSingleEntryArchive(path: "file.txt", content: Data("exact".utf8))
        let zip = try ZipArchive(data: data)
        XCTAssertEqual(try zip.dataCaseInsensitive(for: "file.txt"), Data("exact".utf8))
    }

    func testMissingEntryReturnsNil() throws {
        let (data, _) = buildSingleEntryArchive()
        let zip = try ZipArchive(data: data)
        XCTAssertNil(try zip.data(for: "does/not/exist"))
        XCTAssertNil(try zip.dataCaseInsensitive(for: "does/not/exist"))
    }

    func testZeroByteEntryReturnsEmptyData() throws {
        let (data, _) = buildSingleEntryArchive(content: Data())
        let zip = try ZipArchive(data: data)
        let result = try XCTUnwrap(try zip.data(for: "file.txt"))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Top-level malformed-archive rejection

    func testTooSmallDataIsNotAZipArchive() {
        XCTAssertThrowsError(try ZipArchive(data: Data([0, 1, 2]))) { error in
            guard case ThreeMFError.notAZipArchive = error else {
                return XCTFail("Expected notAZipArchive, got \(error)")
            }
        }
    }

    func testNoEOCDSignatureIsNotAZipArchive() {
        let junk = Data(repeating: 0xAB, count: 100)
        XCTAssertThrowsError(try ZipArchive(data: junk)) { error in
            guard case ThreeMFError.notAZipArchive = error else {
                return XCTFail("Expected notAZipArchive, got \(error)")
            }
        }
    }

    // MARK: - Central directory corruption (caught at `init`)

    func testCentralDirectoryOffsetOutOfRangeThrows() {
        var (data, _) = buildSingleEntryArchive()
        // Patch the EOCD's central-directory offset field (bytes 16..<20 of
        // the 22-byte EOCD record) to a value past the end of the file.
        let eocdStart = data.count - 22
        data.replaceSubrange((eocdStart + 16)..<(eocdStart + 20), with: le32(UInt32(data.count + 1_000)))
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("central directory offset"))
        }
    }

    func testTruncatedCentralDirectoryRecordThrows() {
        var (data, _) = buildSingleEntryArchive()
        // Claim 2 entries while only 1 real central-directory record exists;
        // the loop advances past the (correctly-sized) single record and
        // then finds too little room left for a second 46-byte header.
        let eocdStart = data.count - 22
        data.replaceSubrange((eocdStart + 8)..<(eocdStart + 10), with: le16(2))
        data.replaceSubrange((eocdStart + 10)..<(eocdStart + 12), with: le16(2))
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("truncated central directory record"))
        }
    }

    func testBadCentralDirectorySignatureThrows() {
        var (data, centralDirOffset) = buildSingleEntryArchive()
        data.replaceSubrange(centralDirOffset..<(centralDirOffset + 4), with: le32(0xDEAD_BEEF))
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("bad central directory signature"))
        }
    }

    func testNonUTF8EntryNameThrows() {
        var (data, centralDirOffset) = buildSingleEntryArchive(path: "file.txt")
        // The entry name lives at offset 46 within the central-directory
        // record; corrupt its last byte into an invalid UTF-8 lead byte.
        let nameOffset = centralDirOffset + 46
        data[data.index(data.startIndex, offsetBy: nameOffset + 7)] = 0xFF
        XCTAssertThrowsError(try ZipArchive(data: data)) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("non-UTF8 entry name"))
        }
    }

    // MARK: - Local-header corruption (caught at extraction time)

    func testLocalHeaderOffsetOutOfRangeThrows() throws {
        var (data, centralDirOffset) = buildSingleEntryArchive()
        // The local-header-offset field lives at offset 42 within the
        // central-directory record.
        let offsetFieldStart = centralDirOffset + 42
        data.replaceSubrange(offsetFieldStart..<(offsetFieldStart + 4), with: le32(UInt32(data.count + 1_000)))
        let zip = try ZipArchive(data: data)
        XCTAssertThrowsError(try zip.data(for: "file.txt")) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("local header offset out of range"))
        }
    }

    func testBadLocalFileHeaderSignatureThrows() throws {
        var (data, _) = buildSingleEntryArchive()
        // The local header (and its signature) sits at file offset 0 for a
        // single-entry archive.
        data.replaceSubrange(0..<4, with: le32(0xDEAD_BEEF))
        let zip = try ZipArchive(data: data)
        XCTAssertThrowsError(try zip.data(for: "file.txt")) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("bad local file header signature"))
        }
    }

    func testLocalFileDataOffsetOutOfRangeThrows() throws {
        var (data, _) = buildSingleEntryArchive()
        // The local header's name-length field (offset 26) inflated far
        // beyond the real name/data pushes the computed data start past the
        // end of the buffer, even though the header itself is still valid.
        data.replaceSubrange(26..<28, with: le16(60000))
        let zip = try ZipArchive(data: data)
        XCTAssertThrowsError(try zip.data(for: "file.txt")) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("local file data offset out of range"))
        }
    }

    func testUnsupportedCompressionMethodThrows() throws {
        var (data, centralDirOffset) = buildSingleEntryArchive()
        // The compression-method field lives at offset 10 within the
        // central-directory record (extraction only consults the central
        // directory's method, not the local header's).
        let methodFieldStart = centralDirOffset + 10
        data.replaceSubrange(methodFieldStart..<(methodFieldStart + 2), with: le16(99))
        let zip = try ZipArchive(data: data)
        XCTAssertThrowsError(try zip.data(for: "file.txt")) { error in
            guard case ThreeMFError.unsupportedCompression(let method) = error else {
                return XCTFail("Expected unsupportedCompression, got \(error)")
            }
            XCTAssertEqual(method, 99)
        }
    }

    func testDeflateDecodeSizeMismatchThrows() {
        // A tiny payload whose central-directory record *declares* a much
        // larger uncompressed size (but still well under the ratio-bomb
        // guard's 1 MiB threshold): inflate then decodes far fewer bytes
        // than declared, which must be caught rather than returned silently.
        var writer = ZipWriter()
        writer.addEntry(
            path: "file.txt",
            data: Data("hello, world".utf8),
            method: .deflate,
            declaredUncompressedSizeOverride: 900_000
        )
        let data = writer.finalize()
        let zip = try! ZipArchive(data: data)
        XCTAssertThrowsError(try zip.data(for: "file.txt")) { error in
            guard case ThreeMFError.corruptArchive(let message) = error else {
                return XCTFail("Expected corruptArchive, got \(error)")
            }
            XCTAssertTrue(message.contains("DEFLATE decode size mismatch"))
        }
    }

    // MARK: - Genuine ZIP64 EOCD + locator (not just the per-entry extra field)

    /// Builds an archive whose *EOCD itself* declares ZIP64 sentinel values
    /// (0xFFFF entry count / 0xFFFFFFFF offsets), backed by a real ZIP64
    /// EOCD record and locator — as opposed to `LoaderTests`' coverage of
    /// per-entry ZIP64 extra fields with an otherwise-ordinary EOCD.
    private func buildZip64Archive(path: String = "file.txt", content: Data = Data("zip64 content".utf8)) -> Data {
        let nameData = Data(path.utf8)
        let crc = CRC32.checksum(content)

        var local = Data()
        local += le32(0x0403_4b50)
        local += le16(20); local += le16(0); local += le16(0); local += le16(0); local += le16(0)
        local += le32(crc)
        local += le32(UInt32(content.count))
        local += le32(UInt32(content.count))
        local += le16(UInt16(nameData.count))
        local += le16(0)
        local += nameData
        local += content

        let centralDirOffset = local.count
        var central = Data()
        central += le32(0x0201_4b50)
        central += le16(45); central += le16(45); central += le16(0); central += le16(0); central += le16(0); central += le16(0)
        central += le32(crc)
        central += le32(UInt32(content.count))
        central += le32(UInt32(content.count))
        central += le16(UInt16(nameData.count))
        central += le16(0); central += le16(0); central += le16(0); central += le16(0); central += le32(0)
        central += le32(0) // local header offset
        central += nameData
        let centralDirSize = central.count

        let zip64EOCDOffset = local.count + central.count
        var zip64EOCD = Data()
        zip64EOCD += le32(0x0606_4b50)
        zip64EOCD += le64(44) // size of remaining record
        zip64EOCD += le16(45); zip64EOCD += le16(45)
        zip64EOCD += le32(0); zip64EOCD += le32(0)
        zip64EOCD += le64(1); zip64EOCD += le64(1)
        zip64EOCD += le64(UInt64(centralDirSize))
        zip64EOCD += le64(UInt64(centralDirOffset))

        var locator = Data()
        locator += le32(0x0706_4b50)
        locator += le32(0)
        locator += le64(UInt64(zip64EOCDOffset))
        locator += le32(1)

        var eocd = Data()
        eocd += le32(0x0605_4b50)
        eocd += le16(0); eocd += le16(0)
        eocd += le16(0xFFFF) // sentinel: entries this disk
        eocd += le16(0xFFFF) // sentinel: total entries
        eocd += le32(0xFFFF_FFFF) // sentinel: cd size
        eocd += le32(0xFFFF_FFFF) // sentinel: cd offset
        eocd += le16(0)

        return local + central + zip64EOCD + locator + eocd
    }

    func testGenuineZip64EOCDAndLocatorAreResolved() throws {
        let data = buildZip64Archive()
        let zip = try ZipArchive(data: data)
        XCTAssertEqual(zip.entryPaths, ["file.txt"])
        XCTAssertEqual(try zip.data(for: "file.txt"), Data("zip64 content".utf8))
    }
}
