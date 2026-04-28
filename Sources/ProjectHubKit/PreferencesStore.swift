import AppKit
import Combine
import Foundation

public enum TerminalChoice: String, CaseIterable {
    case iterm2 = "iterm2"
    case terminal = "terminal"

    public var bundleIdentifier: String {
        switch self {
        case .iterm2: return "com.googlecode.iterm2"
        case .terminal: return "com.apple.Terminal"
        }
    }

    public var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .terminal: return "Terminal.app"
        }
    }
}

public struct Preferences: Equatable {
    public var terminalApp: TerminalChoice
    /// Optional global keystroke that summons the user's iTerm hotkey window.
    /// Replayed via `CGEvent` when a process indicator is clicked. Unset =
    /// click-to-summon is disabled and the indicator surfaces a dialog.
    public var iTermHotkeyShortcut: RecordedShortcut?
    /// Round-trip bucket for fields this binary doesn't recognize.
    public var extraFields: [String: Any]

    public init(
        terminalApp: TerminalChoice = .terminal,
        iTermHotkeyShortcut: RecordedShortcut? = nil,
        extraFields: [String: Any] = [:]
    ) {
        self.terminalApp = terminalApp
        self.iTermHotkeyShortcut = iTermHotkeyShortcut
        self.extraFields = extraFields
    }

    public static func == (lhs: Preferences, rhs: Preferences) -> Bool {
        lhs.terminalApp == rhs.terminalApp
            && lhs.iTermHotkeyShortcut == rhs.iTermHotkeyShortcut
    }

    public func toDictionary() -> [String: Any] {
        var dict = extraFields
        dict["terminal_app"] = terminalApp.rawValue
        if let shortcut = iTermHotkeyShortcut {
            dict["iterm_hotkey_shortcut"] = shortcut.toDictionary()
        } else {
            dict.removeValue(forKey: "iterm_hotkey_shortcut")
        }
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> Preferences {
        var extras = dict
        extras.removeValue(forKey: "terminal_app")
        extras.removeValue(forKey: "iterm_hotkey_shortcut")
        let choice = (dict["terminal_app"] as? String)
            .flatMap(TerminalChoice.init(rawValue:)) ?? .terminal
        let shortcut = (dict["iterm_hotkey_shortcut"] as? [String: Any])
            .flatMap(RecordedShortcut.fromDictionary)
        return Preferences(
            terminalApp: choice,
            iTermHotkeyShortcut: shortcut,
            extraFields: extras
        )
    }
}

public final class PreferencesStore: ObservableObject {
    public static let shared = PreferencesStore()

    @Published public private(set) var preferences: Preferences = Preferences()

    internal static let currentSchemaVersion = 1

    private let fileURL: URL
    private var extraTopLevelFields: [String: Any] = [:]
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue: DispatchQueue

    /// Detector used on first launch to pick a sensible default. Overridable
    /// for tests.
    private let detectInstalled: (String) -> Bool

    private init() {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support"))
            .appendingPathComponent("ProjectHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("preferences.json")
        self.saveQueue = DispatchQueue.main
        self.detectInstalled = { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }
        loadOrInitialize()
    }

    /// Test-only initializer targeting a specific file. Saves run synchronously
    /// so round-trip tests don't need to wait for a debounce.
    internal init(
        fileURL: URL,
        detectInstalled: @escaping (String) -> Bool = { _ in false }
    ) {
        self.fileURL = fileURL
        self.saveQueue = DispatchQueue(label: "PreferencesStore.test", qos: .userInitiated)
        self.detectInstalled = detectInstalled
        loadOrInitialize()
    }

    // MARK: - Public API

    public func setTerminalApp(_ choice: TerminalChoice) {
        guard preferences.terminalApp != choice else { return }
        preferences.terminalApp = choice
        scheduleSave()
    }

    public func setITermHotkeyShortcut(_ shortcut: RecordedShortcut?) {
        guard preferences.iTermHotkeyShortcut != shortcut else { return }
        preferences.iTermHotkeyShortcut = shortcut
        scheduleSave()
    }

    public func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        save()
    }

    // MARK: - Persistence

    private func loadOrInitialize() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // First launch: detect iTerm2, else fall back to Terminal.app. Persist.
            let initial: TerminalChoice = detectInstalled(TerminalChoice.iterm2.bundleIdentifier)
                ? .iterm2 : .terminal
            self.preferences = Preferences(terminalApp: initial)
            save()
            return
        }
        self.preferences = Preferences.fromDictionary(raw)

        // Preserve unknown top-level fields for forward compatibility.
        var extras = raw
        extras.removeValue(forKey: "version")
        extras.removeValue(forKey: "terminal_app")
        extras.removeValue(forKey: "iterm_hotkey_shortcut")
        self.extraTopLevelFields = extras
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func save() {
        var payload: [String: Any] = extraTopLevelFields
        payload["version"] = Self.currentSchemaVersion
        for (k, v) in preferences.toDictionary() {
            payload[k] = v
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
