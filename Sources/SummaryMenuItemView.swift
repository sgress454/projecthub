import AppKit

/// A word-wrapped text view used as the content of the AI summary
/// `NSMenuItem` in the project submenu. Non-interactive.
final class SummaryMenuItemView: NSView {
    private let textField = NSTextField(wrappingLabelWithString: "")

    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 20))
        textField.stringValue = text
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.textColor = .secondaryLabelColor
        textField.isSelectable = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.preferredMaxLayoutWidth = 260
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var intrinsicContentSize: NSSize {
        let textSize = textField.intrinsicContentSize
        return NSSize(width: 280, height: textSize.height + 8)
    }
}
