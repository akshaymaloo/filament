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

    private static func meshObjectXML(objectId: Int, vertices: [(Float, Float, Float)], triangles: [(Int, Int, Int)], type: String = "model") -> String {
        var s = "<object id=\"\(objectId)\" type=\"\(type)\">\n  <mesh>\n    <vertices>\n"
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
    public static func minimalCube(deflate: Bool, forceZip64ExtraFields: Bool = false) -> Data {
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
        return archive(deflate: deflate, forceZip64ExtraFields: forceZip64ExtraFields, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// A "billion laughs"-style component DAG: object 1 is the leaf, and each
    /// level above it references the level below `fanOut` times, so a tiny
    /// package describes `fanOut^depth` leaf instances. `leafType` lets the
    /// leaf be an excluded (`support`) object to exercise the visit cap alone.
    public static func componentFanOut(depth: Int, fanOut: Int, leafType: String = "model") -> Data {
        var objects = meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: cubeTriangles, type: leafType)
        for level in 1...depth {
            objects += "<object id=\"\(level + 1)\" type=\"model\">\n  <components>\n"
            for _ in 0..<fanOut {
                objects += "    <component objectid=\"\(level)\"/>\n"
            }
            objects += "  </components>\n</object>\n"
        }
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(objects)
          </resources>
          <build>
            <item objectid="\(depth + 1)"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
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

    /// A realistic multi-plate Bambu/Orca project combining every piece of
    /// per-plate metadata the real parsers understand at once: two plates
    /// (`model_settings.config` plate assignments), a three-color project
    /// palette (`project_settings.config`), a painted triangle on plate 1's
    /// object (mixed with its base-extruder triangles), a plain (unpainted,
    /// non-default-extruder) object on plate 2, per-plate slicer stats
    /// (`Metadata/plate_<id>.json`), per-plate thumbnails, and a package
    /// thumbnail.
    public static func bambuMultiPlateProject() -> Data {
        // Same encoding as `bambuPaintedTriangles`: `paint_color="8"` decodes
        // to extruder 2 (palette index 1 / green) via `PaintColorDecoder`.
        let paintColorForExtruder2 = "8"

        var object1 = "<object id=\"1\" type=\"model\">\n  <mesh>\n    <vertices>\n"
        for v in cubeVertices {
            object1 += "      <vertex x=\"\(v.0)\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
        }
        object1 += "    </vertices>\n    <triangles>\n"
        for (index, t) in cubeTriangles.enumerated() {
            if index == 0 {
                object1 += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\" paint_color=\"\(paintColorForExtruder2)\"/>\n"
            } else {
                object1 += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\"/>\n"
            }
        }
        object1 += "    </triangles>\n  </mesh>\n</object>\n"

        let secondCube = cubeVertices.map { ($0.0 + 50, $0.1, $0.2) }
        let object2 = meshObjectXML(objectId: 2, vertices: secondCube, triangles: cubeTriangles)

        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(object1)
        \(object2)
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
          <object id="1">
            <metadata key="name" value="cubeA.stl"/>
            <metadata key="extruder" value="1"/>
          </object>
          <object id="2">
            <metadata key="name" value="cubeB.stl"/>
            <metadata key="extruder" value="3"/>
          </object>
          <plate>
            <metadata key="plater_id" value="1"/>
            <metadata key="plater_name" value="Cube A"/>
            <model_instance>
              <metadata key="object_id" value="1"/>
            </model_instance>
          </plate>
          <plate>
            <metadata key="plater_id" value="2"/>
            <metadata key="plater_name" value="Cube B"/>
            <model_instance>
              <metadata key="object_id" value="2"/>
            </model_instance>
          </plate>
        </config>
        """

        let projectSettingsJSON = """
        {"filament_colour": ["#FF0000", "#00FF00", "#0000FF"], "filament_type": ["PLA", "PETG", "ABS"]}
        """

        let plate1JSON = """
        {"prediction": 5400, "weight": 15.2, "printer_model_id": "X1C"}
        """
        let plate2JSON = """
        {"prediction": 2700, "weight": 8.4, "printer_model_id": "X1C"}
        """

        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: true).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8)),
            ("Metadata/model_settings.config", Data(modelSettingsXML.utf8)),
            ("Metadata/project_settings.config", Data(projectSettingsJSON.utf8)),
            ("Metadata/plate_1.json", Data(plate1JSON.utf8)),
            ("Metadata/plate_2.json", Data(plate2JSON.utf8)),
            ("Metadata/plate_1.png", TinyPNGFixture.data),
            ("Metadata/plate_2.png", TinyPNGFixture.data),
            ("Metadata/thumbnail.png", TinyPNGFixture.data)
        ])
    }

    /// A cube whose last triangle references vertex index 999 (far beyond
    /// the 8 declared vertices); the other 11 triangles are valid. Exercises
    /// `ModelXMLParser`'s out-of-range triangle filtering (fix 1).
    public static func triangleOutOfRangeCube() -> Data {
        var triangles = cubeTriangles
        triangles[triangles.count - 1] = (0, 1, 999)
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cubeVertices, triangles: triangles))
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// A cube whose last triangle's `v3` attribute is a 20-digit decimal
    /// string that overflows `Int` if parsed naively. Exercises
    /// `ModelXMLParser.parseInt`'s overflow-safe clamping (fix 7); the
    /// resulting (clamped-then-truncated) index is out of range and should
    /// be dropped by the same filtering as `triangleOutOfRangeCube`.
    public static func hugeDigitTriangleIndexCube() -> Data {
        var s = "<object id=\"1\" type=\"model\">\n  <mesh>\n    <vertices>\n"
        for v in cubeVertices {
            s += "      <vertex x=\"\(v.0)\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
        }
        s += "    </vertices>\n    <triangles>\n"
        for (index, t) in cubeTriangles.enumerated() {
            if index == cubeTriangles.count - 1 {
                s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"99999999999999999999\"/>\n"
            } else {
                s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\"/>\n"
            }
        }
        s += "    </triangles>\n  </mesh>\n</object>\n"

        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(s)
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// A cube whose second vertex's `x` attribute has a huge exponent
    /// (`1e999999999`), which would overflow `Double` exponent accumulation
    /// if parsed naively. Exercises `ModelXMLParser.parseDouble`'s clamped
    /// exponent accumulation and the non-finite-coordinate guard (fix 7).
    public static func hugeExponentVertexCube() -> Data {
        var s = "<object id=\"1\" type=\"model\">\n  <mesh>\n    <vertices>\n"
        for (index, v) in cubeVertices.enumerated() {
            if index == 1 {
                s += "      <vertex x=\"1e999999999\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
            } else {
                s += "      <vertex x=\"\(v.0)\" y=\"\(v.1)\" z=\"\(v.2)\"/>\n"
            }
        }
        s += "    </vertices>\n    <triangles>\n"
        for t in cubeTriangles {
            s += "      <triangle v1=\"\(t.0)\" v2=\"\(t.1)\" v3=\"\(t.2)\"/>\n"
        }
        s += "    </triangles>\n  </mesh>\n</object>\n"

        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(s)
          </resources>
          <build>
            <item objectid="1"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// Four objects covering every `<object type=...>` value in the 3MF core
    /// spec: `model` (default, kept), `support`/`other` (excluded from the
    /// rendered mesh/triangle count/dimensions), and `solidsupport` (kept).
    /// Each build item is a plain 12-triangle cube translated along X so
    /// their bounding boxes don't overlap.
    public static func objectTypesFixture() -> Data {
        func cube(offsetX: Float) -> [(Float, Float, Float)] {
            cubeVertices.map { ($0.0 + offsetX, $0.1, $0.2) }
        }
        let modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
        \(meshObjectXML(objectId: 1, vertices: cube(offsetX: 0), triangles: cubeTriangles, type: "model"))
        \(meshObjectXML(objectId: 2, vertices: cube(offsetX: 100), triangles: cubeTriangles, type: "support"))
        \(meshObjectXML(objectId: 3, vertices: cube(offsetX: 200), triangles: cubeTriangles, type: "other"))
        \(meshObjectXML(objectId: 4, vertices: cube(offsetX: 300), triangles: cubeTriangles, type: "solidsupport"))
          </resources>
          <build>
            <item objectid="1"/>
            <item objectid="2"/>
            <item objectid="3"/>
            <item objectid="4"/>
          </build>
        </model>
        """
        return archive(deflate: true, entries: [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML(includeThumbnail: false).utf8)),
            ("3D/3dmodel.model", Data(modelXML.utf8))
        ])
    }

    /// A normal single-cube 3MF package, except the EOCD's trailing archive
    /// comment itself embeds a fake `PK\x05\x06` (EOCD) signature followed by
    /// bytes that don't form a self-consistent record. Exercises
    /// `ZipArchive`'s backward EOCD scan disambiguation (fix 2): it must find
    /// the *real* EOCD (whose declared comment length reaches exactly the end
    /// of the file) rather than stopping at the fake, inner signature.
    public static func minimalCubeWithFakeEOCDInComment() -> Data {
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
        var writer = ZipWriter()
        writer.addEntry(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8), method: .store)
        writer.addEntry(path: "_rels/.rels", data: Data(relsXML(includeThumbnail: false).utf8), method: .store)
        writer.addEntry(path: "3D/3dmodel.model", data: Data(modelXML.utf8), method: .store)

        // A fake signature followed by 16 arbitrary bytes (disk number,
        // central dir counts/size/offset) and a 2-byte "comment length" that,
        // interpreted from the following junk bytes, won't add up to the
        // true end of the file — so it fails the self-consistency check and
        // the real EOCD (whose own comment length is correct) is preferred.
        var comment = Data("Sliced with Fixture Slicer v1.0 — ".utf8)
        comment.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // fake EOCD signature
        comment.append(contentsOf: [UInt8](repeating: 0xAB, count: 16)) // fake fixed fields
        comment.append(contentsOf: [0xFF, 0xFF]) // fake "comment length" (65535, never matches)
        comment.append(Data(" — end of comment".utf8))

        return writer.finalize(trailingComment: comment)
    }

    /// A 3MF package whose model-part central-directory entry declares an
    /// implausible uncompressed size (default 1 GiB) far larger than its
    /// real (tiny, DEFLATE-compressed) payload. Exercises the DEFLATE
    /// ratio-bomb guard (fix 6): the declared ratio vastly exceeds DEFLATE's
    /// ~1032:1 theoretical maximum, so `ZipArchive` must reject it before
    /// ever allocating an output buffer sized to the lie.
    public static func lyingHeaderEntry(claimedUncompressedBytes: Int = 1024 * 1024 * 1024) -> Data {
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
        var writer = ZipWriter()
        writer.addEntry(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8), method: .store)
        writer.addEntry(path: "_rels/.rels", data: Data(relsXML(includeThumbnail: false).utf8), method: .store)
        writer.addEntry(
            path: "3D/3dmodel.model",
            data: Data(modelXML.utf8),
            method: .deflate,
            declaredUncompressedSizeOverride: claimedUncompressedBytes
        )
        return writer.finalize()
    }

    private static func archive(deflate: Bool, forceZip64ExtraFields: Bool = false, entries: [(String, Data)]) -> Data {
        var writer = ZipWriter()
        for (path, data) in entries {
            writer.addEntry(path: path, data: data, method: deflate ? .deflate : .store)
        }
        return writer.finalize(forceZip64ExtraFields: forceZip64ExtraFields)
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

    /// Binary STL with 16 trailing padding bytes appended after the last
    /// triangle record — the exact `84 + 50*count` formula no longer matches
    /// `data.count`, exercising `STLParser`'s tolerant declared-count tier.
    public static func stlBinaryCubeWithTrailingBytes() -> Data {
        var data = stlBinaryCube()
        data.append(contentsOf: [UInt8](repeating: 0xEE, count: 16))
        return data
    }

    /// Binary STL whose 80-byte header starts with the literal ASCII bytes
    /// "solid " (colliding with the ASCII-STL sniff), but whose overall size
    /// still exactly matches `84 + 50*count`, so it must still be classified
    /// as binary (tier 1, exact-size match wins over any prefix heuristic).
    public static func stlBinaryCubeWithSolidPrefix() -> Data {
        var data = stlBinaryCube()
        let prefix = Array("solid ".utf8)
        data.replaceSubrange(0..<prefix.count, with: prefix)
        return data
    }

    /// Binary STL whose declared header triangle count is zeroed out (as if
    /// a buggy writer never filled it in), but whose body size is still a
    /// clean, positive multiple of 50 bytes — exercises `STLParser`'s
    /// body-size fallback tier (count == 0 but the record layout is intact).
    public static func stlBinaryCubeWithZeroDeclaredCount() -> Data {
        var data = stlBinaryCube()
        data.replaceSubrange(80..<84, with: [UInt8](repeating: 0, count: 4))
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

    /// ASCII PLY whose first face's last index is `5000000000` (5e9), which
    /// overflows `UInt32.max` (~4.29e9) — `UInt32(indexValue)` traps on this
    /// unless guarded. Exercises `PLYParser`'s index-range/finiteness check
    /// (fix 7).
    public static func plyASCIICubeWithHugeFaceIndex() -> Data {
        var s = plyHeader(format: "ascii")
        for v in cubeVertices {
            s += "\(v.0) \(v.1) \(v.2)\n"
        }
        for (index, t) in cubeTriangles.enumerated() {
            if index == 0 {
                s += "3 \(t.0) \(t.1) 5000000000\n"
            } else {
                s += "3 \(t.0) \(t.1) \(t.2)\n"
            }
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
