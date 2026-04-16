import AppKit
import Combine
import ProjectHubKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var activeSpaceNumber: Int?
    private var spaceChangeObserver: NSObjectProtocol?

    private var editWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private static let showNameKey = "ProjectHub.showActiveProjectNameInMenuBar"
    private var showNameInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showNameKey) }
    }

    func applicationDidFinishLaunching(_: Notification) {
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

        // Start the Claude status pipeline. This replays events.jsonl, wires
        // the watcher, and begins reacting to claudeEnabled flips.
        StatusCoordinator.shared.start()
        EventLog.rotateIfNeeded()

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

    // Keep the menu-bar name short enough that macOS doesn't hide the entire
    // status item when the bar is crowded. 20 characters fits comfortably next
    // to the icon on most setups; longer names get an ellipsis.
    private static let maxMenuBarNameChars = 20

    private func truncatedForMenuBar(_ name: String) -> String {
        guard name.count > Self.maxMenuBarNameChars else { return name }
        let keep = name.prefix(Self.maxMenuBarNameChars - 1)
        return "\(keep)…"
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        if let image = MenuBarIcon.baseImage() {
            button.image = image
            button.imagePosition = .imageLeft
        }

        if showNameInMenuBar, let project = activeProject() {
            button.title = " \(truncatedForMenuBar(project.name))"
        } else {
            button.title = ""
        }

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
                rowView.configure(
                    projectId: project.id,
                    name: project.name,
                    space: project.space,
                    state: effectiveState,
                    isActive: project.space == activeSpaceNumber
                )
                item.view = rowView
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

        let showName = menu.addItem(
            withTitle: "Show Active Project Name in Menu Bar",
            action: #selector(toggleShowNameInMenuBar),
            keyEquivalent: ""
        )
        showName.target = self
        showName.state = showNameInMenuBar ? .on : .off

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

    // MARK: - Actions

    @objc private func projectClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let project = ProjectStore.shared.projects.first(where: { $0.id == id })
        else { return }

        if !SpaceSwitcher.hasAccessibility() {
            promptForAccessibility()
            return
        }
        SpaceSwitcher.switchTo(space: project.space)
        // Optimistically mark the clicked project's Space as active so the
        // highlight is correct next time the menu opens, without waiting for
        // the detector poll to pick up the switch.
        activeSpaceNumber = project.space
        StatusCoordinator.shared.activeSpaceBecame(project.space)
        updateStatusButton()
        rebuildMenu()
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
