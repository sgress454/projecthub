import AppKit
import Foundation

/// Resolves a `TerminalChoice` to an installed app bundle URL and opens a
/// directory in it. Both iTerm2 and Terminal.app natively interpret an opened
/// directory as "start a shell session rooted there."
public enum TerminalLauncher {
    /// Overridable resolver for tests. Production path uses `NSWorkspace`.
    public static var resolveAppURL: (String) -> URL? = { bundleId in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    public static func isAvailable(_ choice: TerminalChoice) -> Bool {
        resolveAppURL(choice.bundleIdentifier) != nil
    }

    @discardableResult
    public static func open(directoryURL: URL, using choice: TerminalChoice) -> Bool {
        guard let appURL = resolveAppURL(choice.bundleIdentifier) else {
            NSLog("ProjectHub: terminal app not installed for choice %@", choice.rawValue)
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: appURL,
            configuration: config,
            completionHandler: nil
        )
        return true
    }
}
