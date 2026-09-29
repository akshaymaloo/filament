import XCTest
@testable import ThreeMFKit

/// Algorithmic-regression guards, not absolute-speed benchmarks: they load
/// the same shape of mesh at `N` and `4N` triangles and assert the load time
/// scales roughly linearly (ratio well under the ~16x a quadratic algorithm
/// would produce), plus a generous absolute ceiling to catch a pathological
/// regression outright. Debug-build timing is inherently noisy, so each size
/// takes the best of two runs and the ratio threshold is deliberately loose.
final class PerformanceGuardTests: XCTestCase {
    // MARK: - Grid mesh generators

    /// A flat grid of `rows * cols` quads (2 triangles each), laid out as an
    /// indexed vertex/triangle 3MF model part. Not a closed manifold — that
    /// doesn't matter for a load-time guard, only triangle/vertex volume
    /// does. Returns the STORE-compressed archive bytes and the actual
    /// triangle count (which may differ slightly from the request to keep
    /// the grid rectangular).
    private static func gridMesh3MF(triangleCount: Int) -> (data: Data, triangleCount: Int) {
        let quads = max(triangleCount / 2, 1)
        let cols = max(Int(Double(quads).squareRoot().rounded()), 1)
        let rows = max(quads / cols, 1)

        var verticesXML = ""
        verticesXML.reserveCapacity((rows + 1) * (cols + 1) * 32)
        for j in 0...rows {
            for i in 0...cols {
                verticesXML += "<vertex x=\"\(i)\" y=\"\(j)\" z=\"0\"/>"
            }
        }

        func vertexIndex(_ i: Int, _ j: Int) -> Int { j * (cols + 1) + i }
        var trianglesXML = ""
        trianglesXML.reserveCapacity(rows * cols * 2 * 48)
        for j in 0..<rows {
            for i in 0..<cols {
                let v00 = vertexIndex(i, j)
                let v10 = vertexIndex(i + 1, j)
                let v11 = vertexIndex(i + 1, j + 1)
                let v01 = vertexIndex(i, j + 1)
                trianglesXML += "<triangle v1=\"\(v00)\" v2=\"\(v10)\" v3=\"\(v11)\"/>"
                trianglesXML += "<triangle v1=\"\(v00)\" v2=\"\(v11)\" v3=\"\(v01)\"/>"
            }
        }

        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <object id="1" type="model">
              <mesh>
                <vertices>\(verticesXML)</vertices>
                <triangles>\(trianglesXML)</triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        </Types>
        """
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/>
        </Relationships>
        """
        var writer = ZipWriter()
        writer.addEntry(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8), method: .store)
        writer.addEntry(path: "_rels/.rels", data: Data(relsXML.utf8), method: .store)
        writer.addEntry(path: "3D/3dmodel.model", data: Data(modelXML.utf8), method: .store)
        return (writer.finalize(), rows * cols * 2)
    }

    /// A flat grid of the same shape, serialized as a binary STL (which has
    /// no shared vertex buffer — each triangle repeats its own 3 raw
    /// vertices), for exactly `rows * cols * 2` triangles.
    private static func gridMeshBinarySTL(triangleCount: Int) -> Data {
        let quads = max(triangleCount / 2, 1)
        let cols = max(Int(Double(quads).squareRoot().rounded()), 1)
        let rows = max(quads / cols, 1)
        let actualTriangleCount = rows * cols * 2

        var data = Data(count: 80) // header, left zeroed
        var countLE = UInt32(actualTriangleCount).littleEndian
        withUnsafeBytes(of: &countLE) { data.append(contentsOf: $0) }

        var buffer = [UInt8]()
        buffer.reserveCapacity(actualTriangleCount * 50)
        func appendFloat(_ v: Float) {
            var bits = v.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { buffer.append(contentsOf: $0) }
        }
        func appendVertex(_ x: Float, _ y: Float) {
            appendFloat(x)
            appendFloat(y)
            appendFloat(0)
        }
        let zeroNormal = [UInt8](repeating: 0, count: 12)
        for j in 0..<rows {
            for i in 0..<cols {
                let x0 = Float(i), x1 = Float(i + 1)
                let y0 = Float(j), y1 = Float(j + 1)
                buffer.append(contentsOf: zeroNormal)
                appendVertex(x0, y0); appendVertex(x1, y0); appendVertex(x1, y1)
                buffer.append(0); buffer.append(0) // attribute byte count
                buffer.append(contentsOf: zeroNormal)
                appendVertex(x0, y0); appendVertex(x1, y1); appendVertex(x0, y1)
                buffer.append(0); buffer.append(0)
            }
        }
        data.append(contentsOf: buffer)
        return data
    }

    // MARK: - Timing helper

    /// Runs `body` twice and returns the faster wall-clock time, to reduce
    /// scheduling noise on a shared machine.
    private func bestOf2(_ body: () throws -> Void) rethrows -> TimeInterval {
        var best = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<2 {
            let start = Date()
            try body()
            best = min(best, Date().timeIntervalSince(start))
        }
        return best
    }

    // MARK: - Tests

    func testSTLLoadTimeScalesRoughlyLinearly() throws {
        let small = Self.gridMeshBinarySTL(triangleCount: 250_000)
        let large = Self.gridMeshBinarySTL(triangleCount: 1_000_000)

        let smallTime = try bestOf2 {
            _ = try STLParser.parse(data: small)
        }
        let largeTime = try bestOf2 {
            _ = try STLParser.parse(data: large)
        }

        XCTAssertLessThan(largeTime, 60, "1M-triangle binary STL load exceeded the absolute ceiling: \(largeTime)s")
        // Guard against O(n^2)-ish regressions: 4x the triangles should cost
        // well under the 16x a quadratic algorithm would produce. Linear
        // would be ~4x; allow generous headroom for noise/fixed overhead.
        if smallTime > 0.001 {
            let ratio = largeTime / smallTime
            XCTAssertLessThan(ratio, 8, "STL load time scaled non-linearly: 250k=\(smallTime)s 1M=\(largeTime)s ratio=\(ratio)")
        }
    }

    func test3MFLoadTimeScalesRoughlyLinearly() throws {
        let small = Self.gridMesh3MF(triangleCount: 250_000)
        let large = Self.gridMesh3MF(triangleCount: 1_000_000)
        let loader = ThreeMFLoader()

        let smallTime = try bestOf2 {
            _ = try loader.load(data: small.data)
        }
        let largeTime = try bestOf2 {
            _ = try loader.load(data: large.data)
        }

        XCTAssertLessThan(largeTime, 60, "~1M-triangle 3MF load exceeded the absolute ceiling: \(largeTime)s")
        if smallTime > 0.001 {
            let ratio = largeTime / smallTime
            XCTAssertLessThan(ratio, 8, "3MF load time scaled non-linearly: \(small.triangleCount)=\(smallTime)s \(large.triangleCount)=\(largeTime)s ratio=\(ratio)")
        }
    }

    /// Sanity check that the generated fixtures actually contain the
    /// triangle counts the ratio tests assume (catches a generator bug that
    /// would otherwise silently invalidate the ratio assertions above).
    func testGridFixturesHaveExpectedTriangleCounts() throws {
        // A small, cheap size that exercises the same generator math the 1M
        // runs above rely on (10x10 quads = 200 triangles exactly), without
        // paying the cost of regenerating a full million-triangle mesh here.
        let stl = Self.gridMeshBinarySTL(triangleCount: 200)
        let mesh = try STLParser.parse(data: stl)
        XCTAssertEqual(mesh.triangleCount, 200)

        let (data3mf, triangleCount) = Self.gridMesh3MF(triangleCount: 200)
        XCTAssertEqual(triangleCount, 200)
        let doc = try ThreeMFLoader().load(data: data3mf)
        XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 200)
    }
}
