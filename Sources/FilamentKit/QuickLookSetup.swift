import Foundation

/// Non-UI logic behind the app's setup window: which file types Filament
/// handles, the Terminal commands for macOS 26's built-in 3D preview, and
/// default-app status text.
public enum QuickLookSetup {
    public static let supportedExtensions = ["3mf", "stl", "obj", "ply"]

    public static let hydraExtensionID = "com.apple.HydraQLPreviewExtension"

    public static let preferFilamentCommand = "pluginkit -e ignore -i \(hydraExtensionID) && qlmanage -r"
    public static let restoreAppleCommand = "pluginkit -e default -i \(hydraExtensionID) && qlmanage -r"

    /// Extensions whose default app isn't `ownBundleID`, in supported order.
    public static func extensionsNeedingChange(
        defaults: [String: String?],
        ownBundleID: String
    ) -> [String] {
        supportedExtensions.filter { (defaults[$0] ?? nil) != ownBundleID }
    }

    /// One-line status, e.g. "STL and OBJ files open in Xcode." `appNames`
    /// maps bundle IDs to display names; unknown apps read as "another app".
    public static func statusText(
        defaults: [String: String?],
        ownBundleID: String,
        appNames: [String: String] = [:]
    ) -> String {
        let pending = extensionsNeedingChange(defaults: defaults, ownBundleID: ownBundleID)
        if pending.isEmpty {
            return "Filament opens 3MF, STL, OBJ, and PLY files."
        }
        var order: [String] = []
        var groups: [String: [String]] = [:]
        for ext in pending {
            let id = (defaults[ext] ?? nil) ?? ""
            let name = appNames[id] ?? (id.isEmpty ? "no app" : "another app")
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(ext.uppercased())
        }
        let sentences = order.map { name -> String in
            let exts = groups[name] ?? []
            let list = joined(exts)
            let noun = exts.count == 1 ? "file opens" : "files open"
            if name == "no app" {
                return "\(list) \(exts.count == 1 ? "file has" : "files have") no default app."
            }
            return "\(list) \(noun) in \(name)."
        }
        return sentences.joined(separator: " ")
    }

    private static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0, 1: return items.first ?? ""
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + (items.last ?? "")
        }
    }
}
