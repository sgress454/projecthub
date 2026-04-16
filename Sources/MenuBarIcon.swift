import AppKit
import QuartzCore

/// Composes the menu bar status item's image + an optional numeric badge.
/// The badge sits at the top-right as a small colored circle containing the
/// count. Red when any project is red, yellow when only yellow projects.
enum MenuBarIcon {
    static let baseSymbol = "rectangle.3.group"
    private static let pulseAnimationKey = "projecthubWorkingPulse"

    /// Returns a template image of the base symbol (no badge). Caller should
    /// overlay a badge view if there is one — template images can't mix with
    /// tinted colors cleanly, so the badge is better drawn as a sibling view.
    static func baseImage() -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: baseSymbol,
            accessibilityDescription: "ProjectHub"
        ) else { return nil }
        image.isTemplate = true
        return image
    }

    /// Identifier used to find and remove the previous badge view on re-apply.
    static let badgeIdentifier = NSUserInterfaceItemIdentifier("ProjectHubBadge")

    /// Installs / updates a badge subview on the status item's button.
    /// Creates the view on first call; hides it when count is zero.
    /// - Returns: the badge view (useful for tests; callers may ignore).
    @discardableResult
    static func applyBadge(
        to button: NSStatusBarButton,
        count: Int,
        urgent: Bool
    ) -> NSView? {
        // Remove any prior badge we installed (identified by our marker).
        button.subviews
            .filter { $0.identifier == badgeIdentifier }
            .forEach { $0.removeFromSuperview() }
        guard count > 0 else { return nil }

        let badge = BadgeView(count: count, urgent: urgent)
        badge.identifier = badgeIdentifier
        badge.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badge)
        // Anchor top-trailing with a small inset so it overlaps the icon.
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
            badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
        ])
        return badge
    }

    /// Starts or stops a subtle opacity pulse on the button layer. Called
    /// with `animating: true` whenever any project has `working == true`,
    /// false otherwise. Idempotent — safe to call every menu refresh.
    static func setWorkingAnimation(on button: NSStatusBarButton, animating: Bool) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        if animating {
            guard layer.animation(forKey: pulseAnimationKey) == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.45
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: pulseAnimationKey)
        } else {
            layer.removeAnimation(forKey: pulseAnimationKey)
            layer.opacity = 1.0
        }
    }
}

private final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let urgent: Bool

    init(count: Int, urgent: Bool) {
        self.urgent = urgent
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 12))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = (urgent ? NSColor.systemRed : NSColor.systemYellow).cgColor

        label.stringValue = "\(min(count, 99))"
        label.alignment = .center
        label.textColor = .white
        label.font = NSFont.boldSystemFont(ofSize: 8)
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }
}
