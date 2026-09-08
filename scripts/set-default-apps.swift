// Sets Filament as the default application for 3MF and STL files, overriding
// the system default (STL normally opens in Preview). Run after installing:
//   xcrun swift scripts/set-default-apps.swift [path/to/Filament.app]
import AppKit
import UniformTypeIdentifiers
import Foundation

let appPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Filament.app")
let appURL = URL(fileURLWithPath: appPath)

guard FileManager.default.fileExists(atPath: appURL.path) else {
    FileHandle.standardError.write(Data("Filament.app not found at \(appURL.path)\n".utf8))
    exit(1)
}

// Types Filament should become the default opener for.
let requiredIdentifiers = [
    "com.filament3d.3mf",                          // 3MF
    "public.standard-tesselated-geometry-format",  // STL
]
// Optional: if another app has registered a competing 3MF UTI, claim it too.
let optionalIdentifiers = [
    "com.shapr3d.3d-manufacturing.3mf",
    "com.microsoft.package.3dmanufacturing",
    "org.3mf.threemfpackage",
    "org.3mf.threemfformat",
    "org.3mf.model",
    "org.3mf.3mf",
    "com.bambulab.3mf",
]

let sem = DispatchSemaphore(value: 0)
var failures = 0
Task {
    func claim(_ id: String, required: Bool) async {
        guard let type = UTType(id) else {
            if required { print("  ? unknown type \(id)") }
            return
        }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
            print("  ✓ \(id)")
        } catch {
            if required {
                failures += 1
                print("  ! \(id): \(error.localizedDescription)")
            }
        }
    }
    for id in requiredIdentifiers { await claim(id, required: true) }
    for id in optionalIdentifiers { await claim(id, required: false) }
    if let extType = UTType(filenameExtension: "3mf") {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: extType)
            print("  ✓ .3mf (\(extType.identifier))")
        } catch {
            print("  ! .3mf: \(error.localizedDescription)")
        }
    }
    sem.signal()
}
sem.wait()
exit(failures == 0 ? 0 : 1)
