import AppKit
import Combine
import ProjectHubKit
import SwiftUI

extension Notification.Name {
    static let editProjectsWindowWillShow = Notification.Name("ProjectHub.editProjectsWindowWillShow")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var activeSpaceNumber: Int?
    private var spaceChangeObserver: NSObjectProtocol?

    private var editWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    private var screenParamsObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var pendingStatusButtonUpdate: DispatchWorkItem?
    private var pendingVisibilityCheck: DispatchWorkItem?
    private var availableTitleForms: [MenuBarTitleForm] = [.iconOnly]
    private var currentFormIndex: Int = 0

    private static let showNameKey = "ProjectHub.showActiveProjectNameInMenuBar"
    private var showNameInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showNameKey) }
    }

    func applicationDidFinishLaunching(_: Notification) {
        installEditMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusButton()

        ProjectStore.shared.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        // Rebuild the menu + badge whenever any project's runtime state
        // changes (new event ingested, classifier resolved, etc.).
        ProjectStateStore.shared.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        // Re-render the menu when preferences change so row enabled-states for
        // the terminal control update after a terminal-choice switch.
        PreferencesStore.shared.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // Re-render the menu when the Fleet/webpack process indicators change.
        ProcessIndicatorService.shared.$indicators
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // macOS pushes an event whenever the active Space changes — from us,
        // from Ctrl+N, from Mission Control, from trackpad swipes. Use it to
        // keep the highlight current without polling.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshActiveSpace()
            if let n = self.activeSpaceNumber {
                StatusCoordinator.shared.activeSpaceBecame(n)
            }
            self.updateStatusButton()
            self.rebuildMenu()
        }

        // Re-fit the menu-bar title whenever the menu bar's available width can
        // change out from under us: screen attach/detach, resolution change,
        // notch appearance/disappearance, or the system occluding the status
        // item's hosting window.
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleStatusButtonUpdate()
        }

        if let buttonWindow = statusItem.button?.window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: buttonWindow,
                queue: .main
            ) { [weak self] _ in
                // Observation, not reset: if the system just hid us (e.g. another
                // app added a status item and crowded us out), shrink one step.
                // Calling the full update here would re-expand to .full and loop
                // against whatever clipped us in the first place.
                self?.shrinkIfHidden()
            }
        }

        // Start the Claude status pipeline. This replays events.jsonl, wires
        // the watcher, and begins reacting to claudeEnabled flips.
        StatusCoordinator.shared.start()
        EventLog.rotateIfNeeded()

        // Start GitHub sync and summary generation.
        GitHubSync.shared.onSyncComplete = { [weak self] changed in
            self?.updateStatusButton()
            self?.rebuildMenu()
            if changed {
                SummaryGenerator.shared.regenerateAll()
            }
        }
        GitHubSync.shared.start()
        SummaryGenerator.shared.start()
        ProcessIndicatorService.shared.start()

        refreshActiveSpace()
        if let n = activeSpaceNumber {
            StatusCoordinator.shared.activeSpaceBecame(n)
        }
        updateStatusButton()
        rebuildMenu()

        if !UserDefaults.standard.bool(forKey: "ProjectHub.onboardingShown") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    // MARK: - Menu bar button

    private func activeProject() -> Project? {
        guard let n = activeSpaceNumber else { return nil }
        return ProjectStore.shared.projects.first { $0.space == n }
    }

    // Debounce bursts of screen/occlusion notifications (e.g., during Mission
    // Control or space transitions) so the title doesn't flicker mid-animation.
    // Direct callers (project change, name edit) keep calling updateStatusButton()
    // and bypass this path for immediate response.
    private func scheduleStatusButtonUpdate() {
        pendingStatusButtonUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.updateStatusButton()
        }
        pendingStatusButtonUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        if let image = MenuBarIcon.baseImage() {
            button.image = image
            button.imagePosition = .imageLeft
        }

        let name = activeProject()?.name ?? ""
        availableTitleForms = MenuBarTitleFitter.progressiveForms(
            name: name,
            showName: showNameInMenuBar
        )
        currentFormIndex = 0
        applyCurrentTitle()
        scheduleVisibilityCheck()

        // Overlay the badge showing projects needing attention.
        let stateStore = ProjectStateStore.shared
        MenuBarIcon.applyBadge(
            to: button,
            count: stateStore.badgeCount,
            urgent: stateStore.hasAnyRed
        )

        // Pulse the icon while any project is actively working.
        MenuBarIcon.setWorkingAnimation(
            on: button,
            animating: stateStore.hasAnyWorking
        )
    }

    private func applyCurrentTitle() {
        guard let button = statusItem.button else { return }
        guard !availableTitleForms.isEmpty else { button.title = ""; return }
        let idx = min(max(0, currentFormIndex), availableTitleForms.count - 1)
        button.title = availableTitleForms[idx].displayString
    }

    // After setting a title we can't directly ask macOS "did that fit?" — but
    // we can observe it: the status button's hosting window is either visible
    // and positioned at a real x coordinate, or it's offscreen / occluded.
    // Give AppKit one runloop tick to re-lay out, then shrink if hidden.
    private func scheduleVisibilityCheck() {
        pendingVisibilityCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.shrinkIfHidden()
        }
        pendingVisibilityCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func shrinkIfHidden() {
        guard isStatusItemHidden() else { return }
        guard currentFormIndex + 1 < availableTitleForms.count else { return }
        currentFormIndex += 1
        applyCurrentTitle()
        scheduleVisibilityCheck()
    }

    private func isStatusItemHidden() -> Bool {
        guard let window = statusItem.button?.window else { return true }
        if !window.occlusionState.contains(.visible) { return true }
        // A hidden status item commonly has its hosting window parked at x ≤ 0
        // (or at a negative x tucked under the notch) regardless of what the
        // occlusion state reports.
        if window.frame.origin.x <= 0 { return true }
        return false
    }

    // MARK: - Menu

    private func refreshActiveSpace() {
        activeSpaceNumber = SpaceDetector.currentSpaceNumber()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let projects = ProjectStore.shared.projects
        if projects.isEmpty {
            let empty = menu.addItem(
                withTitle: "Add your first project…",
                action: #selector(openEditWindow),
                keyEquivalent: ""
            )
            empty.target = self
        } else {
            let stateStore = ProjectStateStore.shared
            for project in projects.sorted(by: { $0.space < $1.space }) {
                let item = NSMenuItem()
                item.action = #selector(projectClicked(_:))
                item.target = self
                item.representedObject = project.id

                let rowView = ProjectRowView()
                // Disabled projects (claudeEnabled=false or path unset) surface
                // as green in the UI regardless of any ingested events.
                let effectiveState = project.claudeEnabled
                    ? stateStore.state(for: project.id)
                    : .idle

                let choice = PreferencesStore.shared.preferences.terminalApp
                let hasPath = !(project.path ?? "").isEmpty
                let terminalInstalled = TerminalLauncher.isAvailable(choice)
                let terminalEnabled = hasPath && terminalInstalled
                let tooltip: String = {
                    if !hasPath { return "No directory assigned" }
                    if !terminalInstalled {
                        return "\(choice.displayName) not installed \u{2014} change in Preferences"
                    }
                    return "Open \(choice.displayName) in this directory"
                }()
                let capturedPath = project.path

                let indicators = ProcessIndicatorService.shared.indicators[project.id]
                let frontendTooltip: String? = {
                    guard let webpack = indicators?.webpack else { return nil }
                    if webpack.hasExplicitOutput {
                        return "webpack \u{2192} \(webpack.outputDirectory)"
                    }
                    return "webpack \u{2192} \(project.path ?? webpack.outputDirectory)"
                }()
                let backendTooltip: String? = {
                    guard let server = indicators?.server else { return nil }
                    if let port = server.port {
                        return "Fleet server on port \(port)"
                    }
                    return "Fleet server running"
                }()
                let onFrontendClick: (() -> Void)? = (indicators?.webpack != nil)
                    ? { [weak self] in self?.summonITermHotkey() }
                    : nil
                let onBackendClick: (() -> Void)? = (indicators?.server != nil)
                    ? { [weak self] in self?.summonITermHotkey() }
                    : nil

                rowView.configure(
                    projectId: project.id,
                    name: project.name,
                    state: effectiveState,
                    isActive: project.space == activeSpaceNumber,
                    terminalEnabled: terminalEnabled,
                    terminalTooltip: tooltip,
                    onTerminalClick: { [weak self] in
                        guard let path = capturedPath, !path.isEmpty else { return }
                        TerminalLauncher.open(
                            directoryURL: URL(fileURLWithPath: path),
                            using: PreferencesStore.shared.preferences.terminalApp
                        )
                        _ = self
                    },
                    frontendIndicatorTooltip: frontendTooltip,
                    onFrontendIndicatorClick: onFrontendClick,
                    backendIndicatorTooltip: backendTooltip,
                    onBackendIndicatorClick: onBackendClick
                )
                item.view = rowView
                item.submenu = buildSubmenu(for: project)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let edit = menu.addItem(
            withTitle: "Edit Projects…",
            action: #selector(openEditWindow),
            keyEquivalent: ","
        )
        edit.target = self

        if !projects.isEmpty {
            let refresh = menu.addItem(
                withTitle: "Refresh Now",
                action: #selector(refreshNow),
                keyEquivalent: "r"
            )
            refresh.target = self
        }

        let showName = menu.addItem(
            withTitle: "Show Active Project Name in Menu Bar",
            action: #selector(toggleShowNameInMenuBar),
            keyEquivalent: ""
        )
        showName.target = self
        showName.state = showNameInMenuBar ? .on : .off

        let prefs = menu.addItem(
            withTitle: "Preferences\u{2026}",
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        prefs.target = self

        let help = menu.addItem(
            withTitle: "Setup Guide",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        help.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit ProjectHub", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self

        statusItem.menu = menu
    }

    // MARK: - Project submenu

    private func buildSubmenu(for project: Project) -> NSMenu {
        let sub = NSMenu()
        var allURLs: [URL] = []

        // Issues
        let issueInfoCache = GitHubSync.shared.issueInfoCache
        if !project.githubIssues.isEmpty {
            let header = NSMenuItem()
            header.attributedTitle = NSAttributedString(
                string: "Issues",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]
            )
            header.isEnabled = false
            sub.addItem(header)

            for url in project.githubIssues {
                let label = Self.issueLabel(url, info: issueInfoCache[url])
                let item = NSMenuItem(title: label, action: #selector(openURL(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                sub.addItem(item)
                allURLs.append(url)
            }
        }

        // PRs
        let prInfoCache = GitHubSync.shared.prInfoCache
        if !project.githubPRs.isEmpty {
            let header = NSMenuItem()
            header.attributedTitle = NSAttributedString(
                string: "Pull Requests",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]
            )
            header.isEnabled = false
            sub.addItem(header)

            for entry in project.githubPRs {
                let label = Self.prLabel(entry.url, info: prInfoCache[entry.url])
                let item = NSMenuItem(title: label, action: #selector(openURL(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.url
                sub.addItem(item)
                allURLs.append(entry.url)
            }
        }

        // Directory (copy path to clipboard) — shown after Issues and PRs.
        if let path = project.path, !path.isEmpty {
            let header = NSMenuItem()
            header.attributedTitle = NSAttributedString(
                string: "Directory",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]
            )
            header.isEnabled = false
            sub.addItem(header)

            let basename = (path as NSString).lastPathComponent
            let label = Self.ellipsizedDirectoryLabel(basename)
            let item = NSMenuItem(
                title: label,
                action: #selector(copyPath(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = path
            item.toolTip = path
            sub.addItem(item)
        }

        // Links
        if !project.links.isEmpty {
            let header = NSMenuItem()
            header.attributedTitle = NSAttributedString(
                string: "Links",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]
            )
            header.isEnabled = false
            sub.addItem(header)

            for link in project.links {
                let item = NSMenuItem(title: link.label, action: #selector(openURL(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = link.url
                sub.addItem(item)
                allURLs.append(link.url)
            }
        }

        // Open All in Browser
        if allURLs.count >= 2 {
            sub.addItem(.separator())
            let openAll = NSMenuItem(title: "Open All in Browser", action: #selector(openAllURLs(_:)), keyEquivalent: "")
            openAll.target = self
            openAll.representedObject = allURLs
            sub.addItem(openAll)
        }

        // Summary — measure the menu width from existing items so the
        // summary view can calculate its wrapped-text height correctly.
        sub.addItem(.separator())
        let summaryText = project.summary
            ?? "No summary yet \u{2014} attach GitHub issues or start an OpenSpec plan!"
        let menuFont = NSFont.menuFont(ofSize: 0)
        let menuItemPadding: CGFloat = 40 // left + right insets NSMenu uses
        let widestTitle = sub.items.compactMap { item -> CGFloat? in
            guard item.view == nil, !item.isSeparatorItem else { return nil }
            let title = item.attributedTitle?.string ?? item.title
            let size = (title as NSString).size(withAttributes: [.font: menuFont])
            return size.width
        }.max() ?? 0
        let submenuWidth = max(widestTitle + menuItemPadding, 300)

        let summaryItem = NSMenuItem()
        summaryItem.view = SummaryMenuItemView(text: summaryText, width: submenuWidth)
        summaryItem.isEnabled = false
        sub.addItem(summaryItem)

        return sub
    }

    private static let maxIssueTitleChars = 50

    private static func issueLabel(_ url: URL, info: GitHubIssueInfo?) -> String {
        let components = url.pathComponents
        let number: String
        if let idx = components.firstIndex(of: "issues"),
           idx + 1 < components.count {
            number = "#\(components[idx + 1])"
        } else {
            number = url.lastPathComponent
        }
        guard let info else { return number }
        let title = info.title.count > maxIssueTitleChars
            ? "\(info.title.prefix(maxIssueTitleChars - 1))\u{2026}"
            : info.title
        return "\(number) \u{2014} \(title)"
    }

    private static func prLabel(_ url: URL, info: GitHubPRInfo?) -> String {
        let components = url.pathComponents
        let number: String
        if let idx = components.firstIndex(of: "pull"),
           idx + 1 < components.count {
            number = "#\(components[idx + 1])"
        } else {
            number = url.lastPathComponent
        }
        guard let info else { return number }

        // assignee icon + number + title + state + comments
        let assigneeIcon = info.hasAssignees ? "\u{1F464}" : "\u{25CB}" // 👤 or ○
        var label = "\(assigneeIcon) \(number) \u{2014} \(info.title) (\(info.displayState))"
        if info.unresolvedCommentCount > 0 {
            label += "  \u{1F4AC}\(info.unresolvedCommentCount)" // 💬N
        }
        return label
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    private static let maxDirectoryLabelChars = 32

    private static func ellipsizedDirectoryLabel(_ basename: String) -> String {
        guard basename.count > maxDirectoryLabelChars else { return basename }
        let keep = basename.prefix(maxDirectoryLabelChars - 1)
        return "\(keep)\u{2026}"
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAllURLs(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL], !urls.isEmpty else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: NSWorkspace.shared.urlForApplication(toOpen: urls[0]) ?? URL(fileURLWithPath: "/Applications/Safari.app"), configuration: config)
    }

    // MARK: - Actions

    @objc private func projectClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let project = ProjectStore.shared.projects.first(where: { $0.id == id })
        else { return }

        if !SpaceSwitcher.hasAccessibility() {
            promptForAccessibility()
            return
        }
        let result = SpaceSwitcher.switchTo(space: project.space)
        switch result {
        case .posted:
            // Optimistically mark the clicked project's Space as active so the
            // highlight is correct next time the menu opens, without waiting for
            // the detector poll to pick up the switch.
            activeSpaceNumber = project.space
            StatusCoordinator.shared.activeSpaceBecame(project.space)
            updateStatusButton()
            rebuildMenu()
        case .shortcutNotBound(let n), .unsupportedSpace(let n):
            promptForUnboundShortcut(space: n)
        }
    }

    @objc private func refreshNow() {
        GitHubSync.shared.triggerSync()
        SummaryGenerator.shared.regenerateAll()
    }

    @objc private func toggleShowNameInMenuBar() {
        showNameInMenuBar.toggle()
        updateStatusButton()
        rebuildMenu()
    }

    @objc private func openEditWindow() {
        if editWindow == nil {
            let view = EditProjectsView()
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ProjectHub — Projects"
            window.setContentSize(NSSize(width: 520, height: 420))
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            // Follow the user when they switch Spaces, rather than pulling them
            // back to whichever Space the window was last on.
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            editWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editWindow?.makeKeyAndOrderFront(nil)
        // The window is cached, so SwiftUI `onAppear` only fires on first open.
        // Post so the view can reseed its display order each time.
        NotificationCenter.default.post(name: .editProjectsWindowWillShow, object: nil)
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView()
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ProjectHub \u{2014} Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView { [weak self] in
                UserDefaults.standard.set(true, forKey: "ProjectHub.onboardingShown")
                self?.onboardingWindow?.close()
            }
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to ProjectHub"
            window.setContentSize(NSSize(width: 520, height: 460))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    /// Safety net for graceful shutdowns — launchd SIGTERM or the user
    /// picking Quit. `killall` during `install.sh` is SIGKILL and bypasses
    /// this, which is why callers that know they're about to die should
    /// also call `flushPendingSave()` explicitly.
    func applicationWillTerminate(_: Notification) {
        ProjectStore.shared.flushPendingSave()
    }

    // MARK: - Edit menu (enables Cmd+C/V/X/A in text fields)

    /// Menu bar-only apps have no main menu by default, so standard keyboard
    /// shortcuts for Cut/Copy/Paste/Select All are dead. Installing a minimal
    /// Edit menu restores them for all SwiftUI and AppKit text fields.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = {
            let m = NSMenu(title: "Edit")
            m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            return m
        }()
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Accessibility prompt

    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "ProjectHub needs Accessibility permission"
        alert.informativeText = """
        To switch macOS Spaces, ProjectHub needs to send keyboard shortcuts on your behalf.

        Open System Settings → Privacy & Security → Accessibility, and turn ProjectHub on.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SpaceSwitcher.openAccessibilitySettings()
        }
    }

    /// Click handler shared by both process indicators. Posts the user's
    /// configured iTerm hotkey-window keystroke; surfaces an actionable dialog
    /// when the keystroke is unset or Accessibility permission is missing.
    private func summonITermHotkey() {
        switch HotkeyPoster.postITermHotkey() {
        case .posted:
            return
        case .unset:
            promptForUnsetITermHotkey()
        case .notTrusted:
            promptForAccessibility()
        }
    }

    private func promptForUnsetITermHotkey() {
        let alert = NSAlert()
        alert.messageText = "iTerm hotkey shortcut not set"
        alert.informativeText = """
        ProjectHub doesn't know which keystroke summons your iTerm hotkey window.

        Open Preferences and record the same chord you've configured under iTerm2 \u{2192} Settings \u{2192} Keys \u{2192} Hotkey.
        """
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openPreferences()
        }
    }

    private func promptForUnboundShortcut(space n: Int) {
        let alert = NSAlert()
        alert.messageText = "\u{201C}Switch to Desktop \(n)\u{201D} is not enabled"
        alert.informativeText = """
        ProjectHub needs the "Switch to Desktop \(n)" keyboard shortcut to switch to this project's Space.

        Open System Settings → Keyboard → Keyboard Shortcuts → Mission Control, and turn it on.
        """
        alert.addButton(withTitle: "Open Keyboard Shortcuts")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        // Safety refresh on open; the notification handler normally keeps this in sync.
        refreshActiveSpace()
        updateStatusButton()
        rebuildMenu()
    }
}
