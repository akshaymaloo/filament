import Foundation
import Compression

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

    private let data: Data
    private let entriesByPath: [String: CentralEntry]
    private let orderedPaths: [String]

    /// All entry paths, in central-directory (archive) order.
    var entryPaths: [String] { orderedPaths }

    init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw ThreeMFError.notAZipArchive }

        // Scan backward for the EOCD signature within the last 65557 bytes
        // (22-byte record + max 65535-byte comment).
        let searchWindow = min(data.count, 65557)
        let searchStart = data.count - searchWindow
        var eocdOffset: Int? = nil
        var i = data.count - 22
        while i >= searchStart {
            let reader = ByteReader(data.subdata(in: (data.startIndex + i)..<data.endIndex))
            if let sig = try? reader.u32(0), sig == Self.eocdSignature {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdOffset else { throw ThreeMFError.notAZipArchive }

        let eocdReader = ByteReader(data.subdata(in: (data.startIndex + eocd)..<data.endIndex))
        var centralDirCount = Int(try eocdReader.u16(10))
        var centralDirSize = Int(try eocdReader.u32(12))
        var centralDirOffset = Int(try eocdReader.u32(16))

        // Check for ZIP64: locator sits 20 bytes before the EOCD.
        let looksZip64 = centralDirCount == 0xFFFF || centralDirOffset == 0xFFFF_FFFF || centralDirSize == 0xFFFF_FFFF
        if looksZip64, eocd >= 20 {
            let locatorOffset = eocd - 20
            let locatorReader = ByteReader(data.subdata(in: (data.startIndex + locatorOffset)..<data.endIndex))
            if let sig = try? locatorReader.u32(0), sig == Self.zip64LocatorSignature {
                let zip64EocdOffset = Int(try locatorReader.u64(8))
                guard zip64EocdOffset >= 0, zip64EocdOffset < data.count else {
                    throw ThreeMFError.corruptArchive("invalid zip64 EOCD offset")
                }
                let zip64Reader = ByteReader(data.subdata(in: (data.startIndex + zip64EocdOffset)..<data.endIndex))
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
            let reader = ByteReader(data.subdata(in: (data.startIndex + cursor)..<data.endIndex))
            let sig = try reader.u32(0)
            guard sig == Self.centralHeaderSignature else {
                throw ThreeMFError.corruptArchive("bad central directory signature")
            }
            let method = try reader.u16(10)
            let compSize = Int(try reader.u32(20))
            let uncompSize = Int(try reader.u32(24))
            let nameLen = Int(try reader.u16(28))
            let extraLen = Int(try reader.u16(30))
            let commentLen = Int(try reader.u16(32))
            let localOffset = Int(try reader.u32(42))

            let nameData = try reader.slice(46, length: nameLen)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ThreeMFError.corruptArchive("non-UTF8 entry name")
            }

            let entry = CentralEntry(
                path: name,
                compressionMethod: method,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset
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

    private func extract(_ entry: CentralEntry, sizeLimit: Int) throws -> Data {
        if entry.uncompressedSize > sizeLimit {
            throw ThreeMFError.entryTooLarge(path: entry.path, size: entry.uncompressedSize, limit: sizeLimit)
        }
        guard entry.localHeaderOffset >= 0, entry.localHeaderOffset + 30 <= data.count else {
            throw ThreeMFError.corruptArchive("local header offset out of range for \(entry.path)")
        }
        let localReader = ByteReader(data.subdata(in: (data.startIndex + entry.localHeaderOffset)..<data.endIndex))
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
            let bytesReader = ByteReader(data.subdata(in: (data.startIndex + dataStart)..<data.endIndex))
            return try bytesReader.slice(0, length: entry.uncompressedSize)
        case 8: // DEFLATE (raw)
            let bytesReader = ByteReader(data.subdata(in: (data.startIndex + dataStart)..<data.endIndex))
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
