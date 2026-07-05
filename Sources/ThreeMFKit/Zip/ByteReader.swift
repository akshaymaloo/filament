import Foundation

/// Minimal bounds-checked little-endian binary reader over `Data`.
struct ByteReader {
    let data: Data
    let base: Int

    init(_ data: Data) {
        self.data = data
        self.base = data.startIndex
    }

    func u8(_ offset: Int) throws -> UInt8 {
        let i = base + offset
        guard i >= data.startIndex, i < data.endIndex else {
            throw ThreeMFError.corruptArchive("read out of bounds at offset \(offset)")
        }
        return data[i]
    }

    func u16(_ offset: Int) throws -> UInt16 {
        let b0 = try u8(offset)
        let b1 = try u8(offset + 1)
        return UInt16(b0) | (UInt16(b1) << 8)
    }

    func u32(_ offset: Int) throws -> UInt32 {
        let b0 = try u8(offset)
        let b1 = try u8(offset + 1)
        let b2 = try u8(offset + 2)
        let b3 = try u8(offset + 3)
        return UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    }

    func u64(_ offset: Int) throws -> UInt64 {
        let lo = try u32(offset)
        let hi = try u32(offset + 4)
        return UInt64(lo) | (UInt64(hi) << 32)
    }

    /// Little-endian IEEE-754 single precision float at `offset`.
    func f32(_ offset: Int) throws -> Float {
        Float(bitPattern: try u32(offset))
    }

    /// Bounds-checked subrange, relative to `base`.
    func slice(_ offset: Int, length: Int) throws -> Data {
        guard length >= 0 else {
            throw ThreeMFError.corruptArchive("negative length at offset \(offset)")
        }
        let start = base + offset
        let end = start + length
        guard start >= data.startIndex, end <= data.endIndex, start <= end else {
            throw ThreeMFError.corruptArchive("slice out of bounds at offset \(offset) length \(length)")
        }
        return data.subdata(in: start..<end)
    }

    /// Total number of bytes available from `base` onward.
    var count: Int { data.endIndex - base }
}
