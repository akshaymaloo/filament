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
let identifiers = [
    "com.filament3d.3mf",                          // 3MF
    "public.standard-tesselated-geometry-format",  // STL
]

let sem = DispatchSemaphore(value: 0)
var failures = 0
Task {
    for id in identifiers {
        guard let type = UTType(id) else { print("  ? unknown type \(id)"); continue }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
            print("  ✓ \(id)")
        } catch {
            failures += 1
            print("  ! \(id): \(error.localizedDescription)")
        }
    }
    sem.signal()
}
sem.wait()
exit(failures == 0 ? 0 : 1)
