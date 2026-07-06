import Foundation

/// Decodes the Bambu/PrusaSlicer `paint_color` (a.k.a. `mmu_segmentation`)
/// per-triangle attribute used by Bambu Studio / OrcaSlicer to paint
/// individual triangles with a different extruder/filament than the object's
/// base extruder.
public enum PaintColorDecoder {
    /// Decodes a `paint_color` hex string into the dominant painted extruder
    /// index (1-based); `0` means "none/unpainted" (use the object's base
    /// extruder).
    ///
    /// The hex string is a little-endian bitstream: hex characters are
    /// processed right-to-left, and each nibble's bits are read LSB-first.
    /// Conceptually it encodes a binary tree over the triangle's subdivision:
    /// each node starts with a 2-bit `number of split sides` (`nss`); `nss ==
    /// 0` means the node is a leaf, otherwise the node recurses into `nss + 1`
    /// children (after a 2-bit `special_side` field). A leaf then stores a
    /// 2-bit `sc` state: `sc < 3` is the state directly; `sc == 3` extends
    /// with a 4-bit `e` (`state = 3 + e`, unless `e == 14`, which extends
    /// further with an 8-bit value: `state = 17 + v`). The dominant (most
    /// common) painted (`state >= 1`) leaf state across the whole tree is
    /// returned as the triangle's extruder index.
    public static func decode(_ hex: String) -> Int {
        guard !hex.isEmpty else { return 0 }
        var bits: [Bool] = []
        bits.reserveCapacity(hex.count * 4)
        for ch in hex.reversed() {
            guard let v = ch.hexDigitValue else { return 0 }
            bits.append(v & 1 != 0); bits.append(v & 2 != 0); bits.append(v & 4 != 0); bits.append(v & 8 != 0)
        }
        var pos = 0
        func read(_ n: Int) -> Int {
            var r = 0
            for i in 0..<n {
                guard pos < bits.count else { break }
                if bits[pos] { r |= (1 << i) }
                pos += 1
            }
            return r
        }
        var states: [Int] = []
        func decode(depth: Int) {
            guard depth < 32, pos < bits.count else { return }
            let nss = read(2)
            if nss == 0 {
                let sc = read(2)
                let state: Int
                if sc < 3 {
                    state = sc
                } else {
                    let e = read(4)
                    if e == 14 { state = 17 + read(8) } else { state = 3 + e }
                }
                states.append(state)
            } else {
                _ = read(2)
                for _ in 0...nss { decode(depth: depth + 1) }
            }
        }
        decode(depth: 0)
        let painted = states.filter { $0 >= 1 }
        guard !painted.isEmpty else { return 0 }
        var counts: [Int: Int] = [:]
        for s in painted { counts[s, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? 0
    }
}
