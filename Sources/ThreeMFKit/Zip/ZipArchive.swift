import Foundation
import Compression

/// Tracks the cumulative uncompressed bytes extracted from one archive load,
/// across every `data(for:)`/`dataCaseInsensitive(for:)` call, so a package
/// with many individually-small-but-numerous entries (or one entry whose
/// declared size is a lie) can't inflate far past a caller's total budget.
/// A reference type so it can be shared across a `ZipArchive` value and its
/// lazily-parsed external model parts without threading a return value
/// through every call site.
final class ExtractionBudget {
    private var extracted = 0
    let limit: Int

    init(limit: Int = .max) {
        self.limit = limit
    }

    /// Charges `bytes` against the budget *before* the caller allocates them,
    /// throwing if the running total would exceed `limit`.
    func charge(_ bytes: Int, path: String) throws {
        extracted += bytes
        guard extracted <= limit else {
            throw ThreeMFError.archiveTooLarge(limit: limit)
        }
    }
}

/// A read-only, dependency-free ZIP archive reader tailored to OPC/3MF packages.
struct ZipArchive {
    private struct CentralEntry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
    private static let zip64EocdSignature: UInt32 = 0x0606_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    /// Zip64 extended information extra field (APPNOTE.TXT 4.5.3).
    private static let zip64ExtraFieldID: UInt16 = 0x0001
    private static let zip64FieldSentinel32: UInt32 = 0xFFFF_FFFF
    private static let zip64FieldSentinel16: UInt16 = 0xFFFF
    /// DEFLATE's theoretical maximum compression ratio is ~1032:1 (a stream
    /// of empty blocks). A declared ratio well beyond that is either a lying
    /// header or a zip-bomb; reject it before ever attempting to inflate.
    private static let maxPlausibleDeflateRatio = 1100
    /// Only apply the ratio check once the declared uncompressed size is
    /// large enough that a legitimate tiny/incompressible file's overhead
    /// (a few bytes) can't trip it.
    private static let ratioCheckThreshold = 1024 * 1024

    private let data: Data
    private let entriesByPath: [String: CentralEntry]
    private let orderedPaths: [String]
    private let budget: ExtractionBudget

    /// All entry paths, in central-directory (archive) order.
    var entryPaths: [String] { orderedPaths }

    init(data: Data, budget: ExtractionBudget = ExtractionBudget()) throws {
        self.data = data
        self.budget = budget
        guard data.count >= 22 else { throw ThreeMFError.notAZipArchive }

        let eocd = try Self.locateEOCD(in: data)

        let eocdReader = ByteReader(data, offset: eocd)
        var centralDirCount = Int(try eocdReader.u16(10))
        var centralDirSize = Int(try eocdReader.u32(12))
        var centralDirOffset = Int(try eocdReader.u32(16))

        // Check for ZIP64: locator sits 20 bytes before the EOCD.
        let looksZip64 = centralDirCount == 0xFFFF || centralDirOffset == 0xFFFF_FFFF || centralDirSize == 0xFFFF_FFFF
        if looksZip64, eocd >= 20 {
            let locatorOffset = eocd - 20
            let locatorReader = ByteReader(data, offset: locatorOffset)
            if let sig = try? locatorReader.u32(0), sig == Self.zip64LocatorSignature {
                let zip64EocdOffset = Int(try locatorReader.u64(8))
                guard zip64EocdOffset >= 0, zip64EocdOffset < data.count else {
                    throw ThreeMFError.corruptArchive("invalid zip64 EOCD offset")
                }
                let zip64Reader = ByteReader(data, offset: zip64EocdOffset)
                let zip64Sig = try zip64Reader.u32(0)
                guard zip64Sig == Self.zip64EocdSignature else {
                    throw ThreeMFError.corruptArchive("expected zip64 EOCD signature")
                }
                centralDirCount = Int(try zip64Reader.u64(32))
                centralDirSize = Int(try zip64Reader.u64(40))
                centralDirOffset = Int(try zip64Reader.u64(48))
            }
        }

        guard centralDirOffset >= 0, centralDirOffset <= data.count else {
            throw ThreeMFError.corruptArchive("central directory offset out of range")
        }

        var byPath: [String: CentralEntry] = [:]
        var order: [String] = []
        order.reserveCapacity(centralDirCount)

        var cursor = centralDirOffset
        var remaining = centralDirCount
        // Defensively bound iteration by the declared central directory size too,
        // in case the entry count is corrupt.
        let cdEnd = min(data.count, centralDirOffset + max(centralDirSize, 0))
        while remaining > 0 {
            guard cursor + 46 <= data.count else {
                throw ThreeMFError.corruptArchive("truncated central directory record")
            }
            let reader = ByteReader(data, offset: cursor)
            let sig = try reader.u32(0)
            guard sig == Self.centralHeaderSignature else {
                throw ThreeMFError.corruptArchive("bad central directory signature")
            }
            let method = try reader.u16(10)
            let compressedSize32 = try reader.u32(20)
            let uncompressedSize32 = try reader.u32(24)
            let nameLen = Int(try reader.u16(28))
            let extraLen = Int(try reader.u16(30))
            let commentLen = Int(try reader.u16(32))
            let diskStart = try reader.u16(34)
            let localOffset32 = try reader.u32(42)

            let nameData = try reader.slice(46, length: nameLen)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ThreeMFError.corruptArchive("non-UTF8 entry name")
            }

            let extraData = extraLen > 0
                ? try reader.slice(46 + nameLen, length: extraLen)
                : Data()
            let sizes = try Self.resolveZip64Sizes(
                extra: extraData,
                compressedSize: compressedSize32,
                uncompressedSize: uncompressedSize32,
                localHeaderOffset: localOffset32,
                diskStart: diskStart
            )

            let entry = CentralEntry(
                path: name,
                compressionMethod: method,
                compressedSize: sizes.compressedSize,
                uncompressedSize: sizes.uncompressedSize,
                localHeaderOffset: sizes.localHeaderOffset
            )
            byPath[name] = entry
            order.append(name)

            cursor += 46 + nameLen + extraLen + commentLen
            remaining -= 1
            if centralDirSize > 0, cursor > cdEnd { break }
        }

        self.entriesByPath = byPath
        self.orderedPaths = order
    }

    func entries(matching predicate: (String) -> Bool) -> [String] {
        orderedPaths.filter(predicate)
    }

    func data(for path: String, sizeLimit: Int = .max) throws -> Data? {
        guard let entry = entriesByPath[path] else { return nil }
        return try extract(entry, sizeLimit: sizeLimit)
    }

    func dataCaseInsensitive(for path: String, sizeLimit: Int = .max) throws -> Data? {
        if let d = try data(for: path, sizeLimit: sizeLimit) { return d }
        let lower = path.lowercased()
        guard let match = orderedPaths.first(where: { $0.lowercased() == lower }) else { return nil }
        return try data(for: match, sizeLimit: sizeLimit)
    }

    /// Scans backward through the last up-to-65557 bytes (22-byte record +
    /// max 65535-byte comment) for the EOCD signature, without copying any
    /// bytes. Some archives are followed by a comment that itself happens to
    /// contain the 4-byte EOCD signature (or is crafted to); disambiguate by
    /// preferring the candidate whose declared comment length reaches
    /// exactly the end of the data (i.e. it owns the trailing bytes as its
    /// own comment). If no candidate is internally consistent, fall back to
    /// the last (rightmost) signature match, matching prior behavior.
    private static func locateEOCD(in data: Data) throws -> Int {
        let searchWindow = min(data.count, 65557)
        let searchStart = data.count - searchWindow
        var candidates: [Int] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress, raw.count >= 4 else { return }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var i = data.count - 22
            while i >= searchStart {
                if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                    candidates.append(i)
                }
                i -= 1
            }
        }
        guard !candidates.isEmpty else { throw ThreeMFError.notAZipArchive }

        for candidate in candidates {
            let reader = ByteReader(data, offset: candidate)
            if let commentLen = try? reader.u16(20), candidate + 22 + Int(commentLen) == data.count {
                return candidate
            }
        }
        // `candidates` was built scanning from the highest offset downward,
        // so the first entry is the rightmost (last) match in the file.
        return candidates[0]
    }

    /// Resolves compressed size / uncompressed size / local-header offset from
    /// the Zip64 extended information extra field (header id 0x0001) when the
    /// corresponding 32-bit central-directory field is the 0xFFFFFFFF sentinel.
    ///
    /// Per APPNOTE.TXT 4.5.3 the extra-field payload lists those 64-bit values
    /// in a fixed order, but *only* for fields that were overflowed:
    /// uncompressed size, compressed size, local header offset, disk start.
    /// Some writers (notably OnShape) emit the sentinel even when the real
    /// value fits in 32 bits, so this path is required for small archives too.
    private static func resolveZip64Sizes(
        extra: Data,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        localHeaderOffset: UInt32,
        diskStart: UInt16
    ) throws -> (compressedSize: Int, uncompressedSize: Int, localHeaderOffset: Int) {
        let needsUncompressed = uncompressedSize == zip64FieldSentinel32
        let needsCompressed = compressedSize == zip64FieldSentinel32
        let needsOffset = localHeaderOffset == zip64FieldSentinel32

        if !needsUncompressed && !needsCompressed && !needsOffset {
            return (Int(compressedSize), Int(uncompressedSize), Int(localHeaderOffset))
        }

        var cursor = 0
        let reader = ByteReader(extra)
        while cursor + 4 <= extra.count {
            let headerID = try reader.u16(cursor)
            let dataSize = Int(try reader.u16(cursor + 2))
            let payloadOffset = cursor + 4
            guard dataSize >= 0, payloadOffset + dataSize <= extra.count else {
                throw ThreeMFError.corruptArchive("truncated extra field")
            }
            if headerID == zip64ExtraFieldID {
                var pos = 0
                func take64(_ field: String) throws -> Int {
                    guard pos + 8 <= dataSize else {
                        throw ThreeMFError.corruptArchive("truncated zip64 extra field (\(field))")
                    }
                    let value = try reader.u64(payloadOffset + pos)
                    pos += 8
                    guard value <= UInt64(Int.max) else {
                        throw ThreeMFError.corruptArchive("zip64 \(field) exceeds addressable size")
                    }
                    return Int(value)
                }

                let uncompressed = needsUncompressed ? try take64("uncompressed size") : Int(uncompressedSize)
                let compressed = needsCompressed ? try take64("compressed size") : Int(compressedSize)
                let offset = needsOffset ? try take64("local header offset") : Int(localHeaderOffset)
                // Disk start number is unused by this reader but may be present.
                if diskStart == zip64FieldSentinel16, pos + 4 <= dataSize {
                    pos += 4
                }
                return (compressed, uncompressed, offset)
            }
            cursor = payloadOffset + dataSize
        }

        throw ThreeMFError.corruptArchive("missing zip64 extra field for 0xFFFFFFFF central-directory sentinel")
    }

    private func extract(_ entry: CentralEntry, sizeLimit: Int) throws -> Data {
        if entry.uncompressedSize > sizeLimit {
            throw ThreeMFError.entryTooLarge(path: entry.path, size: entry.uncompressedSize, limit: sizeLimit)
        }
        // DEFLATE's theoretical max ratio is ~1032:1; a declared ratio well
        // beyond that on a non-trivial entry is a lying header (or a bomb)
        // and must be rejected before `inflate` allocates the declared size.
        if entry.compressionMethod == 8, entry.uncompressedSize > Self.ratioCheckThreshold {
            let ratio = entry.compressedSize > 0 ? entry.uncompressedSize / entry.compressedSize : Int.max
            guard ratio <= Self.maxPlausibleDeflateRatio else {
                throw ThreeMFError.corruptArchive("implausible compression ratio for \(entry.path) (\(entry.uncompressedSize):\(entry.compressedSize))")
            }
        }
        // Charge the *declared* uncompressed size against the aggregate
        // budget before allocating any output buffer for it.
        try budget.charge(entry.uncompressedSize, path: entry.path)

        guard entry.localHeaderOffset >= 0, entry.localHeaderOffset + 30 <= data.count else {
            throw ThreeMFError.corruptArchive("local header offset out of range for \(entry.path)")
        }
        let localReader = ByteReader(data, offset: entry.localHeaderOffset)
        let sig = try localReader.u32(0)
        guard sig == Self.localHeaderSignature else {
            throw ThreeMFError.corruptArchive("bad local file header signature for \(entry.path)")
        }
        let nameLen = Int(try localReader.u16(26))
        let extraLen = Int(try localReader.u16(28))
        let dataStart = entry.localHeaderOffset + 30 + nameLen + extraLen
        guard dataStart >= 0, dataStart <= data.count else {
            throw ThreeMFError.corruptArchive("local file data offset out of range for \(entry.path)")
        }

        if entry.uncompressedSize == 0 {
            return Data()
        }

        switch entry.compressionMethod {
        case 0: // STORE
            let bytesReader = ByteReader(data, offset: dataStart)
            return try bytesReader.slice(0, length: entry.uncompressedSize)
        case 8: // DEFLATE (raw)
            let bytesReader = ByteReader(data, offset: dataStart)
            let compressed = try bytesReader.slice(0, length: entry.compressedSize)
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw ThreeMFError.unsupportedCompression(method: entry.compressionMethod)
        }
    }

    private static func inflate(_ compressed: Data, expectedSize: Int, path: String) throws -> Data {
        var output = [UInt8](repeating: 0, count: expectedSize)
        let decodedCount: Int = output.withUnsafeMutableBytes { dstRaw -> Int in
            compressed.withUnsafeBytes { srcRaw -> Int in
                guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    dstBase, expectedSize,
                    srcBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedSize else {
            throw ThreeMFError.corruptArchive("DEFLATE decode size mismatch for \(path): expected \(expectedSize), got \(decodedCount)")
        }
        return Data(output)
    }
}
