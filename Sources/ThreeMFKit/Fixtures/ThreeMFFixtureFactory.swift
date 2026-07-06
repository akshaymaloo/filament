import Foundation

/// Produces small, valid in-memory `.3mf` (ZIP/OPC) fixtures for the
/// validation executable and XCTest suite, without needing real sample files.
public enum ThreeMFFixtureFactory {
    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
      <Default Extension="png" ContentType="image/png"/>
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    </Types>
    """

    private static func relsXML(includeThumbnail: Bool) -> String {
        var rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/>
        """
        if includeThumbnail {
            rels += "\n  <Relationship Id=\"rel-2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail\" Target=\"/Metadata/thumbnail.png\"/>"
        }
        rels += "\n</Relationships>"
        return rels
    }

    /// An axis-aligned cube from (0,0,0) to (20,20,20), 8 vertices / 12 triangles.
    private static let cubeVertices: [(Float, Float, Float)] = [
        (0, 0, 0), (20, 0, 0), (20, 20, 0), (0, 20, 0),
        (0, 0, 20), (20, 0, 20), (20, 20, 20), (0, 20, 20)
    ]
    private static let cubeTriangles: [(Int, Int, Int)] = [
        (0, 1, 2), (0, 2, 3),
        (4, 6, 5), (4, 7, 6),
        (0, 5, 1), (0, 4, 5),
        (3, 2, 6), (3, 6, 7),
        (0, 3, 7), (0, 7, 4),
        (1, 6, 2), (1, 5, 6)
    ]

    private static func meshObjectXML(objectId: Int, vertices: [(Float, Float, Float)], triangles: [(Int, Int, Int)]) -> String {
        var s = "<object id=\"\(objectId)\" type=\"model\">\n  <mesh>\n    <vertices>\n"
        for v in vertices {
            s += "      <vertex x=\"\(v.0)\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
        }
        s += "    </vertices>\n    <triangles>\n"
        for t in triangles {
            s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\"/>\n"
        }
        s += "    </triangles>\n  </mesh>\n</object>\n"
        return s
    }

    /// A single-object cube (spec-style: 8 vertices / 12 triangles), no Bambu metadata.
    public static func minimalCube(deflate: Bool) -> Data {
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: cubeTriangles))
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        return archive(deflate: deflate, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// An object referencing another object via `<components>` with a translating
    /// transform, exercising component/build-item transform composition.
    public static func translatedComponent() -> Data {
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: cubeTriangles))
            <object id="2" type="model">
              <components>
                <component objectid="1" transform="1 0 0 0 1 0 0 0 1 10 20 30"/>
              </components>
            </object>
          </resources>
          <build>
            <item objectid="2"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// A 3MF Production Extension package where the root model's only object
    /// is a `<components>` reference (via `p:path`) to an object defined in a
    /// SEPARATE model part (`3D/Objects/sub.model`), exercising cross-part
    /// component resolution (e.g. Bambu Studio-exported files).
    public static func productionExtensionCube() -> Data {
        let rootModelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" requiredextensions="p">
          <resources>
            <object id="2" type="model">
              <components>
                <component p:path="/3D/Objects/sub.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
              </components>
            </object>
          </resources>
          <build>
            <item objectid="2"/>
          </build>
        </model>
        """

        let subModelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: cubeTriangles))
          </resources>
          <build/>
        </model>
        """

        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(rootModelXML.utf8)),
            ("3D/Objects/sub.model", Data(subModelXML.utf8))
        ])
    }

    /// Two cube objects split across two Bambu plates, with embedded PNG
    /// thumbnails, per-plate JSON stats, and a package-level OPC thumbnail.
    public static func bambuTwoPlates() -> Data {
        let secondCube = cubeVertices.map { ($0.0 + 50, $0.1, $0.2) }
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: cubeTriangles))
        \(meshObjectXML(objectId: 2, vertices: secondCube, triangles: cubeTriangles))
          </resources>
          <build>
            <item objectid="1"/>
            <item objectid="2"/>
          </build>
        </model>
        """

        let modelSettingsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <config>
          <plate>
            <metadata key="plater_id" value="1"/>
            <metadata key="plater_name" value="Cube A"/>
            <model_instance>
              <metadata key="object_id" value="1"/>
            </model_instance>
          </plate>
          <plate>
            <metadata key="plater_id" value="2"/>
            <metadata key="plater_name" value=""/>
            <model_instance>
              <metadata key="object_id" value="2"/>
            </model_instance>
          </plate>
        </config>
        """

        let plate1JSON = """
        {"prediction": 3600, "weight": 12.5, "printer_model_id": "X1C", "filament_used_g": [12.5]}
        """

        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: true).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8)),
            ("Metadata/model_settings.config", Data(modelSettingsXML.utf8)),
            ("Metadata/plate_1.png", TinyPNGFixture.data),
            ("Metadata/plate_2.png", TinyPNGFixture.data),
            ("Metadata/plate_1.json", Data(plate1JSON.utf8)),
            ("Metadata/thumbnail.png", TinyPNGFixture.data)
        ])
    }

    /// A single-object cube with a Bambu-style paint override: the first
    /// triangle carries `paint_color="8"` (decodes to extruder 2 / green, see
    /// `PaintColorDecoder`), while every other triangle is unpainted and thus
    /// falls back to the object's base extruder (1 / red, from
    /// `model_settings.config`). `project_settings.config` supplies the
    /// two-color filament palette.
    public static func bambuPaintedTriangles() -> Data {
        // `paint_color="8"` is the shortest hex bitstream that decodes to
        // extruder 2: reading its single nibble LSB-first gives bits
        // [0,0,0,1]; the first two bits are `nss=0` (leaf triangle) and the
        // next two are `sc=2` (`sc < 3`, so `state = sc = 2`), i.e. "painted
        // with extruder 2". See `PaintColorDecoder.decode`.
        let paintColorForExtruder2 = "8"

        var s = "<object id=\"1\" type=\"model\">\n  <mesh>\n    <vertices>\n"
        for v in cubeVertices {
            s += "      <vertex x=\"\(v.0)\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
        }
        s += "    </vertices>\n    <triangles>\n"
        for (index, t) in cubeTriangles.enumerated() {
            if index == 0 {
                s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\" paint_color=\"\(paintColorForExtruder2)\"/>\n"
            } else {
                s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\"/>\n"
            }
        }
        s += "    </triangles>\n  </mesh>\n</object>\n"
        let objectXML = s

        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(objectXML)
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """

        let modelSettingsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <config>
          <object id="1">
            <metadata key="name" value="painted_cube.stl"/>
            <metadata key="extruder" value="1"/>
          </object>
          <plate>
            <metadata key="plater_id" value="1"/>
            <metadata key="plater_name" value="Painted Cube"/>
            <model_instance>
              <metadata key="object_id" value="1"/>
            </model_instance>
          </plate>
        </config>
        """

        let projectSettingsJSON = """
        {"filament_colour": ["#FF0000", "#00FF00"]}
        """

        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8)),
            ("Metadata/model_settings.config", Data(modelSettingsXML.utf8)),
            ("Metadata/project_settings.config", Data(projectSettingsJSON.utf8))
        ])
    }

    private static func archive(deflate: Bool, entries: [(String, Data)]) -> Data {
        var writer = ZipWriter()
        for (path, data) in entries {
            writer.addEntry(path: path, data: data, method: deflate ? .deflate : .store)
        }
        return writer.finalize()
    }

    // MARK: - STL / OBJ / PLY cube fixtures
    //
    // All share the same unit cube geometry as the 3MF fixtures above
    // (`cubeVertices`/`cubeTriangles`), just serialized in each format's
    // on-disk representation.

    /// Binary STL: 80-byte header, UInt32 LE triangle count, then 50-byte
    /// records (12-byte normal + 3×12-byte vertices + 2-byte attribute count).
    public static func stlBinaryCube() -> Data {
        var data = Data(count: 80) // header, left zeroed
        var triangleCountLE = UInt32(cubeTriangles.count).littleEndian
        withUnsafeBytes(of: &triangleCountLE) { data.append(contentsOf: $0) }

        for (i0, i1, i2) in cubeTriangles {
            // Normal is unused by our parser; write zeros.
            data.append(contentsOf: [UInt8](repeating: 0, count: 12))
            for idx in [i0, i1, i2] {
                let v = cubeVertices[idx]
                for component in [v.0, v.1, v.2] {
                    var bits = component.bitPattern.littleEndian
                    withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
                }
            }
            data.append(contentsOf: [0, 0]) // attribute byte count
        }
        return data
    }

    /// ASCII STL: `solid` header, one `facet`/`outer loop` block per triangle.
    public static func stlASCIICube() -> Data {
        var s = "solid cube\n"
        for (i0, i1, i2) in cubeTriangles {
            s += "  facet normal 0 0 0\n    outer loop\n"
            for idx in [i0, i1, i2] {
                let v = cubeVertices[idx]
                s += "      vertex \(v.0) \(v.1) \(v.2)\n"
            }
            s += "    endloop\n  endfacet\n"
        }
        s += "endsolid cube\n"
        return Data(s.utf8)
    }

    /// Wavefront OBJ: `v` lines then 1-based `f` lines.
    public static func objCube() -> Data {
        var s = "# cube\n"
        for v in cubeVertices {
            s += "v \(v.0) \(v.1) \(v.2)\n"
        }
        for (i0, i1, i2) in cubeTriangles {
            s += "f \(i0 + 1) \(i1 + 1) \(i2 + 1)\n"
        }
        return Data(s.utf8)
    }

    private static func plyHeader(format: String) -> String {
        """
        ply
        format \(format) 1.0
        element vertex \(cubeVertices.count)
        property float x
        property float y
        property float z
        element face \(cubeTriangles.count)
        property list uchar int vertex_indices
        end_header

        """
    }

    /// ASCII PLY.
    public static func plyASCIICube() -> Data {
        var s = plyHeader(format: "ascii")
        for v in cubeVertices {
            s += "\(v.0) \(v.1) \(v.2)\n"
        }
        for (i0, i1, i2) in cubeTriangles {
            s += "3 \(i0) \(i1) \(i2)\n"
        }
        return Data(s.utf8)
    }

    /// Binary little-endian PLY.
    public static func plyBinaryLECube() -> Data {
        plyBinaryCube(format: "binary_little_endian", bigEndian: false)
    }

    /// Binary big-endian PLY.
    public static func plyBinaryBECube() -> Data {
        plyBinaryCube(format: "binary_big_endian", bigEndian: true)
    }

    private static func plyBinaryCube(format: String, bigEndian: Bool) -> Data {
        var data = Data(plyHeader(format: format).utf8)
        for v in cubeVertices {
            for component in [v.0, v.1, v.2] {
                var bits = bigEndian ? component.bitPattern.bigEndian : component.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        for (i0, i1, i2) in cubeTriangles {
            data.append(3) // uchar list count
            for idx in [i0, i1, i2] {
                var bits = bigEndian ? UInt32(idx).bigEndian : UInt32(idx).littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}
