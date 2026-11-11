import AppKit

extension SectionController {
    /// Combined divider bar + chevron (`|‹` when collapsed, `|›` when expanded) for the Hidden section boundary.
    /// Always 16 pt wide so flipping state or the divider never shifts the icons beside it.
    static func toggleImage(collapsed: Bool, showDivider: Bool) -> NSImage {
        let symbolName = collapsed ? "chevron.left" : "chevron.right"
        let chevron = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MenuTuck")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            if showDivider {
                let bar = NSRect(x: 1.5, y: 2, width: 1.5, height: rect.height - 4)
                NSBezierPath(roundedRect: bar, xRadius: 0.75, yRadius: 0.75).fill()
            }
            if let chevron {
                let cSize = chevron.size
                let dst = NSRect(
                    x: 5.5 + max(0, (10 - cSize.width) / 2),
                    y: (rect.height - cSize.height) / 2,
                    width: cSize.width,
                    height: cSize.height
                )
                chevron.draw(in: dst)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Double vertical bar `‖` for the Always-Hidden section divider.
    static let alwaysHiddenDividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            let leftBar = NSRect(x: rect.midX - 2.25, y: 2, width: 1.5, height: rect.height - 4)
            let rightBar = NSRect(x: rect.midX + 0.75, y: 2, width: 1.5, height: rect.height - 4)
            NSBezierPath(roundedRect: leftBar, xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: rightBar, xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
