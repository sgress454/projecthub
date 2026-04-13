import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var activeSpaceNumber: Int?
    private var activeSpaceTimer: Timer?

    private var editWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton()

        ProjectStore.shared.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        rebuildMenu()

        if !UserDefaults.standard.bool(forKey: "ProjectHub.onboardingShown") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    // MARK: - Menu bar button

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "ProjectHub") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "PH"
        }
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
            for project in projects.sorted(by: { $0.space < $1.space }) {
                let marker = (project.space == activeSpaceNumber) ? "●" : " "
                let title = "\(marker)  \(project.name)    Space \(project.space)"
                let item = menu.addItem(
                    withTitle: title,
                    action: #selector(projectClicked(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = project.id
                if project.space == activeSpaceNumber {
                    item.state = .on
                }
            }
        }

        menu.addItem(.separator())

        let edit = menu.addItem(
            withTitle: "Edit Projects…",
            action: #selector(openEditWindow),
            keyEquivalent: ","
        )
        edit.target = self

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
        rebuildMenu()
    }

    @objc private func openEditWindow() {
        if editWindow == nil {
            let view = EditProjectsView()
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "ProjectHub — Projects"
            window.setContentSize(NSSize(width: 440, height: 380))
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

// MARK: - NSMenuDelegate (active-space refresh)

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_: NSMenu) {
        // Refresh once immediately in case Space changed via another tool, then
        // tick periodically while the menu is open.
        refreshActiveSpace()
        rebuildMenu()
        activeSpaceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let latest = SpaceDetector.currentSpaceNumber()
            if latest != self.activeSpaceNumber {
                self.activeSpaceNumber = latest
                self.rebuildMenu()
            }
        }
    }

    func menuDidClose(_: NSMenu) {
        activeSpaceTimer?.invalidate()
        activeSpaceTimer = nil
    }
}
