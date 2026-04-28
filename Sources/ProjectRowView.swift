import AppKit
import ProjectHubKit

/// Custom NSView used as the content of each project `NSMenuItem`. Renders:
///
///   [●  working-spinner] name (bold if active)        🎨  🌐  🖥
///
/// Handles hover highlight via a tracking area, and click dispatch by
/// cancelling the menu and firing the item's action.
///
/// Using a custom view is what lets us show an actual spinning
/// `NSProgressIndicator` for the `working` sub-state — a native NSMenuItem
/// only supports static images via its `.image` property.
final class ProjectRowView: NSView {
    private let statusIndicator = StatusIndicatorView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()
    private let terminalButton = NSButton()
    private let frontendButton = NSButton()
    private let backendButton = NSButton()

    /// The project this row represents — captured in `configure(…)` so the
    /// dismiss-button action can route the click back to the coordinator
    /// without walking up through `enclosingMenuItem`.
    private var projectId: UUID?

    /// Closure invoked when the trailing terminal button is clicked (only
    /// when enabled). Cleared when the row is reconfigured.
    private var onTerminalClick: (() -> Void)?
    /// Closure invoked when the 🎨 (frontend / webpack) indicator is clicked.
    /// Cleared when the row is reconfigured.
    private var onFrontendIndicatorClick: (() -> Void)?
    /// Closure invoked when the 🌐 (backend / Fleet server) indicator is clicked.
    /// Cleared when the row is reconfigured.
    private var onBackendIndicatorClick: (() -> Void)?

    private var isHighlighted: Bool = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        autoresizingMask = [.width]
        wantsLayer = true
        buildSubviews()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    private func buildSubviews() {
        nameLabel.font = NSFont.menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail

        dismissButton.title = ""
        dismissButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Dismiss"
        )
        dismissButton.imageScaling = .scaleProportionallyUpOrDown
        dismissButton.isBordered = false
        dismissButton.bezelStyle = .inline
        dismissButton.imagePosition = .imageOnly
        dismissButton.setButtonType(.momentaryChange)
        dismissButton.contentTintColor = .tertiaryLabelColor
        dismissButton.toolTip = "Mark as read"
        dismissButton.isHidden = true
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)

        terminalButton.title = ""
        terminalButton.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "Open in terminal"
        )
        terminalButton.image?.isTemplate = true
        terminalButton.imageScaling = .scaleProportionallyUpOrDown
        terminalButton.isBordered = false
        terminalButton.bezelStyle = .inline
        terminalButton.imagePosition = .imageOnly
        terminalButton.setButtonType(.momentaryChange)
        terminalButton.contentTintColor = .secondaryLabelColor
        terminalButton.target = self
        terminalButton.action = #selector(terminalClicked)
        terminalButton.setContentHuggingPriority(.required, for: .horizontal)

        // 🎨 (frontend / webpack) and 🌐 (backend / Fleet server) indicator
        // buttons. Hidden by default; revealed by `configure(...)` when the
        // current process scan attributes a matching process to the project.
        configureIndicatorButton(frontendButton, emoji: "\u{1F3A8}", action: #selector(frontendIndicatorClicked))
        configureIndicatorButton(backendButton, emoji: "\u{1F310}", action: #selector(backendIndicatorClicked))

        // Trailing icon cluster lives in a horizontal NSStackView pinned to
        // the row's far-right edge. NSStackView collapses hidden arranged
        // subviews, so a row with only the frontend indicator visible packs
        // it directly next to the terminal icon (no empty backend slot).
        let trailingStack = NSStackView(views: [frontendButton, backendButton, terminalButton])
        trailingStack.orientation = .horizontal
        trailingStack.spacing = 6
        trailingStack.alignment = .centerY
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailingStack)

        let stack = NSStackView(views: [statusIndicator, nameLabel, dismissButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 14),
            dismissButton.heightAnchor.constraint(equalToConstant: 14),

            frontendButton.widthAnchor.constraint(equalToConstant: 18),
            frontendButton.heightAnchor.constraint(equalToConstant: 18),
            backendButton.widthAnchor.constraint(equalToConstant: 18),
            backendButton.heightAnchor.constraint(equalToConstant: 18),
            terminalButton.widthAnchor.constraint(equalToConstant: 16),
            terminalButton.heightAnchor.constraint(equalToConstant: 16),

            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func configureIndicatorButton(_ button: NSButton, emoji: String, action: Selector) {
        button.title = emoji
        button.font = NSFont.menuFont(ofSize: 0)
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .noImage
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = action
        button.isHidden = true
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Configuration

    func configure(
        projectId: UUID,
        name: String,
        state: ProjectRuntimeState,
        isActive: Bool,
        terminalEnabled: Bool = false,
        terminalTooltip: String? = nil,
        onTerminalClick: (() -> Void)? = nil,
        frontendIndicatorTooltip: String? = nil,
        onFrontendIndicatorClick: (() -> Void)? = nil,
        backendIndicatorTooltip: String? = nil,
        onBackendIndicatorClick: (() -> Void)? = nil
    ) {
        self.projectId = projectId
        statusIndicator.configure(status: state.status, working: state.working)
        nameLabel.stringValue = name
        nameLabel.font = isActive
            ? NSFont.boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
            : NSFont.menuFont(ofSize: 0)

        // Dismiss is meaningful on any attention-demanding state (red or
        // yellow). Hidden on green — nothing to clear.
        dismissButton.isHidden = (state.status == .green)

        // Terminal button: visually disabled (greyed) when no path or the
        // configured terminal isn't installed. Greyed doubles as the cue
        // that this project is missing a folder.
        self.onTerminalClick = onTerminalClick
        terminalButton.isEnabled = terminalEnabled
        terminalButton.alphaValue = terminalEnabled ? 1.0 : 0.35
        terminalButton.toolTip = terminalTooltip

        // Process indicators: shown only when the current scan has attributed
        // a matching process to this project. Each is its own click target
        // (see hitTest below) — clicking does NOT switch Spaces.
        self.onFrontendIndicatorClick = onFrontendIndicatorClick
        frontendButton.isHidden = (onFrontendIndicatorClick == nil)
        frontendButton.toolTip = frontendIndicatorTooltip

        self.onBackendIndicatorClick = onBackendIndicatorClick
        backendButton.isHidden = (onBackendIndicatorClick == nil)
        backendButton.toolTip = backendIndicatorTooltip
    }

    // MARK: - Mouse / highlight

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited, .activeAlways, .inVisibleRect,
        ]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }

    override func mouseEntered(with _: NSEvent) { isHighlighted = true }
    override func mouseExited(with _: NSEvent) { isHighlighted = false }

    override func mouseUp(with _: NSEvent) {
        guard let item = enclosingMenuItem else { return }
        item.menu?.cancelTracking()
        if let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    /// Let the dismiss, terminal, and process-indicator buttons capture their
    /// own clicks instead of bubbling into the row's `mouseUp` (which would
    /// switch Spaces). hitTest returns the button for any point inside its
    /// visible frame.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)

        if terminalButton.isEnabled {
            let expanded = terminalButton.frame.insetBy(dx: -4, dy: -4)
            if expanded.contains(local) {
                return terminalButton
            }
        }

        if !backendButton.isHidden {
            let expanded = backendButton.frame.insetBy(dx: -4, dy: -4)
            if expanded.contains(local) {
                return backendButton
            }
        }

        if !frontendButton.isHidden {
            let expanded = frontendButton.frame.insetBy(dx: -4, dy: -4)
            if expanded.contains(local) {
                return frontendButton
            }
        }

        if !dismissButton.isHidden {
            let expanded = dismissButton.frame.insetBy(dx: -4, dy: -4)
            if expanded.contains(local) {
                return dismissButton
            }
        }
        return super.hitTest(point)
    }

    @objc private func terminalClicked() {
        guard terminalButton.isEnabled else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onTerminalClick?()
    }

    @objc private func dismissClicked() {
        guard let projectId else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        StatusCoordinator.shared.dismiss(projectId: projectId)
    }

    @objc private func frontendIndicatorClicked() {
        enclosingMenuItem?.menu?.cancelTracking()
        onFrontendIndicatorClick?()
    }

    @objc private func backendIndicatorClicked() {
        enclosingMenuItem?.menu?.cancelTracking()
        onBackendIndicatorClick?()
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
            nameLabel.textColor = .white
        } else {
            nameLabel.textColor = .labelColor
        }
    }
}

/// Leading indicator for the status row — swaps between a colored filled
/// circle (`.green` / `.yellow` / `.red`) and a small animated
/// NSProgressIndicator when the project is `working`.
final class StatusIndicatorView: NSView {
    private let imageView = NSImageView()
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(equalToConstant: 14),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }

    func configure(status: ProjectStatus, working: Bool) {
        if working {
            imageView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            imageView.isHidden = false
            imageView.image = Self.dotImage(for: status)
        }
    }

    /// Cached filled-circle images in the three accent colors.
    private static let dotImages: [ProjectStatus: NSImage] = {
        ProjectStatus.allCases.reduce(into: [:]) { out, s in
            out[s] = makeDot(color: color(for: s))
        }
    }()

    private static func dotImage(for status: ProjectStatus) -> NSImage {
        dotImages[status]!
    }

    private static func color(for status: ProjectStatus) -> NSColor {
        switch status {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        }
    }

    private static func makeDot(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
