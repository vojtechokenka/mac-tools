import AppKit

enum DSSnapshot {
    static let desk = DS.dynamic(light: 0xECECEC, dark: 0x1E1E1E)

    @discardableResult
    static func write(view: NSView, to url: URL, dark: Bool, scale: CGFloat = 2, background: NSColor? = DS.paper, panel: Bool = false) -> Bool {
        guard let bitmap = render(view: view, dark: dark, scale: scale, background: background, panel: panel),
              let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    static func render(view: NSView, dark: Bool, scale: CGFloat = 2, background: NSColor? = DS.paper, panel: Bool = false) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
        if view.frame.width <= 0 || view.frame.height <= 0 {
            let fitting = view.fittingSize
            view.setFrameSize(NSSize(width: max(view.frame.width, fitting.width), height: max(view.frame.height, fitting.height)))
        }
        let size = view.frame.size
        guard size.width > 0, size.height > 0, let content = bitmap(size: size, scale: scale) else { return nil }

        let previousAppearance = view.appearance
        var host: NSWindow?
        var hosted: NSView?
        if view.window == nil {
            var top = view
            while let parent = top.superview { top = parent }
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: top.frame.size), styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView?.addSubview(top)
            host = window
            hosted = top
        }
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()

        view.cacheDisplay(in: view.bounds, to: content)

        view.appearance = previousAppearance
        hosted?.removeFromSuperview()
        host?.contentView = nil

        guard background != nil || panel else { return content }
        let outset = DSSurface.outset
        let canvasSize = panel ? NSSize(width: size.width + outset.left + outset.right, height: size.height + outset.top + outset.bottom) : size
        guard let canvas = bitmap(size: canvasSize, scale: scale), let context = NSGraphicsContext(bitmapImageRep: canvas) else { return content }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            let full = NSRect(origin: .zero, size: canvasSize)
            if panel {
                let rect = NSRect(x: outset.left, y: outset.bottom, width: size.width, height: size.height)
                DSDraw.fill(full, desk)
                DSSurface.draw(around: rect)
                if let background { DSDraw.fill(rect, radius: DS.panelRadius, background) }
                NSBezierPath(roundedRect: rect, xRadius: DS.panelRadius, yRadius: DS.panelRadius).addClip()
                content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            } else {
                if let background { DSDraw.fill(full, background) }
                content.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            }
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    private static func bitmap(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        guard let raw = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded(.up)),
            pixelsHigh: Int((size.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        let tagged = raw.retagging(with: .sRGB) ?? raw
        tagged.size = size
        return tagged
    }
}
