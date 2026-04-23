import Foundation

public enum MenuBarTitleForm: Equatable {
    case full(String)
    case truncated(String)
    case iconOnly

    public var displayString: String {
        switch self {
        case .full(let s), .truncated(let s): return s
        case .iconOnly: return ""
        }
    }
}

public enum MenuBarTitleFitter {
    // Returns candidate forms from longest to shortest, ending in `.iconOnly`.
    // Truncations halve each step so convergence is fast even for long names —
    // a 40-char name produces 7 steps (full, 20…, 10…, 5…, 2…, 1…, iconOnly).
    // Callers apply a form, observe whether the status item actually rendered,
    // and advance to the next form if hidden. Halving trades minor length
    // optimality for fast visibility recovery on crowded menu bars.
    public static func progressiveForms(name: String, showName: Bool) -> [MenuBarTitleForm] {
        guard showName, !name.isEmpty else { return [.iconOnly] }
        var forms: [MenuBarTitleForm] = [.full(" \(name)")]
        let chars = Array(name)
        var n = chars.count
        while n > 1 {
            n = max(1, n / 2)
            forms.append(.truncated(" \(String(chars.prefix(n)))\u{2026}"))
        }
        forms.append(.iconOnly)
        return forms
    }
}
