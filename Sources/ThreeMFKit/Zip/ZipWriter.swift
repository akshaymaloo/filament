import Foundation
import Compression

/// Minimal ZIP writer used only to build in-memory `.3mf` fixtures for tests
/// and the validation executable. Supports STORE and DEFLATE entries.
struct ZipWriter {
    enum Method {
        case store
        case deflate
    }

    private struct PendingEntry {
        let path: String
        let method: Method
        let uncompressed: Data
        let compressed: Data
        let crc32: UInt32
        let localHeaderOffset: Int
    }

    private var entries: [PendingEntry] = []
    private var body = Data()

    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let eocdSignature: UInt32 = 0x0605_4b50

    mutating func addEntry(path: String, data: Data, method: Method) {
        let crc = CRC32.checksum(data)
        let compressed: Data
        switch method {
        case .store:
            compressed = data
        case .deflate:
            compressed = Self.deflate(data) ?? data
        }
        let offset = body.count
        let nameData = Data(path.utf8)

        var local = Data()
        local.appendLE(Self.localHeaderSignature)
        local.appendLE(UInt16(20))                      // version needed
        local.appendLE(UInt16(0))                       // flags
        local.appendLE(UInt16(method == .deflate ? 8 : 0))
        local.appendLE(UInt16(0))                       // mod time
        local.appendLE(UInt16(0))                       // mod date
        local.appendLE(crc)
        local.appendLE(UInt32(compressed.count))
        local.appendLE(UInt32(data.count))
        local.appendLE(UInt16(nameData.count))
        local.appendLE(UInt16(0))                        // extra field length
        local.append(nameData)
        local.append(compressed)

        body.append(local)
        entries.append(PendingEntry(path: path, method: method, uncompressed: data, compressed: compressed, crc32: crc, localHeaderOffset: offset))
    }

    /// Serializes the archive: local entries followed by the central directory and EOCD.
    func finalize() -> Data {
        var output = body
        let centralDirStart = output.count

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            var central = Data()
            central.appendLE(Self.centralHeaderSignature)
            central.appendLE(UInt16(20))                 // version made by
            central.appendLE(UInt16(20))                 // version needed
            central.appendLE(UInt16(0))                  // flags
            central.appendLE(UInt16(entry.method == .deflate ? 8 : 0))
            central.appendLE(UInt16(0))                  // mod time
            central.appendLE(UInt16(0))                  // mod date
            central.appendLE(entry.crc32)
            central.appendLE(UInt32(entry.compressed.count))
            central.appendLE(UInt32(entry.uncompressed.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))                   // extra field length
            central.appendLE(UInt16(0))                   // comment length
            central.appendLE(UInt16(0))                   // disk number start
            central.appendLE(UInt16(0))                   // internal attributes
            central.appendLE(UInt32(0))                   // external attributes
            central.appendLE(UInt32(entry.localHeaderOffset))
            central.append(nameData)
            output.append(central)
        }

        let centralDirSize = output.count - centralDirStart

        var eocd = Data()
        eocd.appendLE(Self.eocdSignature)
        eocd.appendLE(UInt16(0))                          // disk number
        eocd.appendLE(UInt16(0))                          // disk with CD
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(centralDirSize))
        eocd.appendLE(UInt32(centralDirStart))
        eocd.appendLE(UInt16(0))                          // comment length
        output.append(eocd)

        return output
    }

    private static func deflate(_ data: Data) -> Data? {
        if data.isEmpty { return Data() }
        // Raw DEFLATE output can occasionally exceed the input size for tiny/incompressible
        // inputs; size the destination buffer generously.
        let capacity = max(data.count * 2 + 64, 256)
        var output = [UInt8](repeating: 0, count: capacity)
        let encodedCount = output.withUnsafeMutableBytes { dstRaw -> Int in
            data.withUnsafeBytes { srcRaw -> Int in
                guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    dstBase, capacity,
                    srcBase, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard encodedCount > 0 else { return nil }
        return Data(output.prefix(encodedCount))
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
