import Foundation

/// A menu bar section, from the user's point of view.
enum MenuSection: String, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always Hidden"
        }
    }

    var symbol: String {
        switch self {
        case .visible: return "eye"
        case .hidden: return "eye.slash"
        case .alwaysHidden: return "lock"
        }
    }

    /// Short spatial hint relating this section to the physical menu bar dividers.
    var spatialHint: String {
        switch self {
        case .visible: return "Right of |›"
        case .hidden: return "Left of |›"
        case .alwaysHidden: return "Left of ‖"
        }
    }

    /// The divider glyph associated with this section in the menu bar.
    var dividerGlyph: String {
        switch self {
        case .visible: return "|›"
        case .hidden: return "|‹"
        case .alwaysHidden: return "‖"
        }
    }
}

enum BarState: String, CaseIterable, Identifiable {
    /// Hidden and always-hidden icons are off screen.
    case collapsed
    /// Hidden icons show. Always-hidden icons stay off screen.
    case expanded
    /// All icons show.
    case showAll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .collapsed: return "Collapsed"
        case .expanded: return "Expanded"
        case .showAll: return "Show All"
        }
    }
}

/// Positions of MenuTuck's own status items, in global CG coordinates (top-left origin).
struct DividerLayout {
    var toggle: CGRect
    var alwaysHidden: CGRect?
}
