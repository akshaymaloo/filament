import Foundation
import simd

/// Exposes pass/fail results for internal-only components (ZIP reader/writer,
/// transform math) so the `ThreeMFValidate` executable and XCTest suite can
/// assert on them without promoting `Matrix4`/`ZipArchive`/`ZipWriter` to the
/// public API surface.
public enum ThreeMFInternalDiagnostics {
    public static func runSelfTests() -> [(name: String, passed: Bool)] {
        var results: [(name: String, passed: Bool)] = []

        // Matrix4: identity leaves a vertex unchanged.
        let v = SIMD3<Float>(3, 4, 5)
        let identityResult = Matrix4.identity.apply(to: v)
        results.append(("Matrix4.identity leaves vertex unchanged", identityResult == v))

        // Matrix4: pure translation adds the offset.
        let translation = Matrix4.parse("1 0 0 0 1 0 0 0 1 10 20 30")
        let translated = translation.apply(to: v)
        results.append(("Matrix4 pure translation adds offset", translated == v + SIMD3<Float>(10, 20, 30)))

        // Matrix4: composing two translations sums the offsets.
        let translationA = Matrix4.parse("1 0 0 0 1 0 0 0 1 1 2 3")
        let translationB = Matrix4.parse("1 0 0 0 1 0 0 0 1 10 20 30")
        let composed = translationA.compose(translationB).apply(to: v)
        results.append(("Matrix4 compose sums translations", composed == v + SIMD3<Float>(11, 22, 33)))

        // ZIP: STORE and DEFLATE round-trip through writer -> reader returns identical bytes.
        for method: ZipWriter.Method in [.store, .deflate] {
            let label = method == .store ? "store" : "deflate"
            let payload = Data("Hello, 3MF! \(String(repeating: "x", count: 200))".utf8)
            var writer = ZipWriter()
            writer.addEntry(path: "test/entry.txt", data: payload, method: method)
            let archiveData = writer.finalize()
            do {
                let archive = try ZipArchive(data: archiveData)
                let roundTripped = try archive.data(for: "test/entry.txt")
                results.append(("ZIP \(label) round-trip returns identical bytes", roundTripped == payload))
            } catch {
                results.append(("ZIP \(label) round-trip returns identical bytes", false))
            }
        }

        return results
    }
}
