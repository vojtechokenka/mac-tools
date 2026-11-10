import AppKit

final class DSBrandTarget: NSObject {
    static let shared = DSBrandTarget()

    @objc func openSite(_ sender: Any?) {
        NSWorkspace.shared.open(DSBrand.url)
    }
}

enum DSBrand {
    static let url = URL(string: "https://vojtechokenka.com")!
    static let credit = "by Vojtěch Okénka"

    static func logo(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(srgbRed: 0x14 / 255.0, green: 0x6E / 255.0, blue: 0xF5 / 255.0, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: size / 8, yRadius: size / 8).fill()
            NSColor.white.setFill()
            let radius = size / 4
            NSBezierPath(ovalIn: NSRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: credit, action: #selector(DSBrandTarget.openSite(_:)), keyEquivalent: "")
        item.target = DSBrandTarget.shared
        item.image = logo(size: 16)
        return item
    }
}
