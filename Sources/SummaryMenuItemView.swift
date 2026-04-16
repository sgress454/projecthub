import AppKit

/// A word-wrapped text view used as the content of the AI summary
/// `NSMenuItem` in the project submenu. Non-interactive.
///
/// NSMenu determines item height from the view's frame at assignment time,
/// so we compute height explicitly from the text. Width is set to
/// `autoresizingMask = [.width]` so the menu can stretch us wider if
/// other items (like long PR titles) are wider.
final class SummaryMenuItemView: NSView {
    private let textField = NSTextField(wrappingLabelWithString: "")
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 4

    init(text: String, width: CGFloat) {
        let textWidth = width - Self.horizontalPadding * 2

        super.init(frame: .zero)
        autoresizingMask = [.width]

        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.textColor = .secondaryLabelColor
        textField.isSelectable = false
        textField.isEditable = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byWordWrapping
        textField.preferredMaxLayoutWidth = textWidth

        let textHeight = textField.sizeThatFits(
            NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        ).height
        let totalHeight = textHeight + Self.verticalPadding * 2

        frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
        textField.frame = NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: textWidth,
            height: textHeight
        )
        addSubview(textField)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        let textWidth = bounds.width - Self.horizontalPadding * 2
        guard textWidth > 0 else { return }
        textField.preferredMaxLayoutWidth = textWidth
        let textHeight = textField.sizeThatFits(
            NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        ).height
        textField.frame = NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding,
            width: textWidth,
            height: textHeight
        )
    }
}
