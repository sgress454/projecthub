import AppKit
import ProjectHubKit

/// Custom NSView used as the content of each project `NSMenuItem`. Renders:
///
///   [●  working-spinner] name (bold if active)       Space N
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
    private let spaceLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()

    /// The project this row represents — captured in `configure(…)` so the
    /// dismiss-button action can route the click back to the coordinator
    /// without walking up through `enclosingMenuItem`.
    private var projectId: UUID?

    private var isHighlighted: Bool = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
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
        spaceLabel.font = NSFont.menuFont(ofSize: 0)
        spaceLabel.textColor = .secondaryLabelColor
        spaceLabel.setContentHuggingPriority(.required, for: .horizontal)

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

        let stack = NSStackView(views: [statusIndicator, nameLabel, spaceLabel, dismissButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 14),
            dismissButton.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    // MARK: - Configuration

    func configure(
        projectId: UUID,
        name: String,
        space: Int,
        state: ProjectRuntimeState,
        isActive: Bool
    ) {
        self.projectId = projectId
        statusIndicator.configure(status: state.status, working: state.working)
        nameLabel.stringValue = name
        nameLabel.font = isActive
            ? NSFont.boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
            : NSFont.menuFont(ofSize: 0)
        spaceLabel.stringValue = "Space \(space)"

        // Dismiss is meaningful on any attention-demanding state (red or
        // yellow). Hidden on green — nothing to clear.
        dismissButton.isHidden = (state.status == .green)
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

    /// Let the dismiss button capture its own clicks instead of bubbling
    /// into the row's `mouseUp` (which would switch Spaces). hitTest
    /// returns the button for any point inside its visible frame.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !dismissButton.isHidden {
            let local = convert(point, from: superview)
            // Give the button a generous hit zone so it's actually tappable.
            let expanded = dismissButton.frame.insetBy(dx: -4, dy: -4)
            if expanded.contains(local) {
                return dismissButton
            }
        }
        return super.hitTest(point)
    }

    @objc private func dismissClicked() {
        guard let projectId else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        StatusCoordinator.shared.dismiss(projectId: projectId)
    }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
            nameLabel.textColor = .white
            spaceLabel.textColor = .white
        } else {
            nameLabel.textColor = .labelColor
            spaceLabel.textColor = .secondaryLabelColor
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
