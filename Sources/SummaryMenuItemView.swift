import AppKit

/// A word-wrapped text view used as the content of the AI summary
/// `NSMenuItem` in the project submenu. Non-interactive.
final class SummaryMenuItemView: NSView {
    private let textField = NSTextField(wrappingLabelWithString: "")
    private static let viewWidth: CGFloat = 380
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 4

    init(text: String) {
        let width = Self.viewWidth
        let textWidth = width - Self.horizontalPadding * 2

        super.init(frame: .zero)

        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.textColor = .secondaryLabelColor
        textField.isSelectable = false
        textField.isEditable = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byWordWrapping
        textField.preferredMaxLayoutWidth = textWidth

        // Calculate the actual height the text needs.
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
}
