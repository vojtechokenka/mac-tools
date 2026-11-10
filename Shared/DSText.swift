import AppKit
import CoreText

enum DSText {
    private static let contextColorKey = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)

    static func attributed(_ string: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, contextColorKey: true])
    }

    static func line(_ string: String, font: NSFont) -> CTLine {
        CTLineCreateWithAttributedString(attributed(string, font: font))
    }

    static func width(_ string: String, font: NSFont) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(line(string, font: font), nil, nil, nil))
    }

    static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func snap(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    static func baselineOffset(height: CGFloat, font: NSFont, lineHeight: CGFloat? = nil) -> CGFloat {
        let line = lineHeight ?? font.pointSize * 1.25
        let ascent = (font.ascender * 2).rounded()
        let descent = (-font.descender * 2).rounded()
        let halfLeading = ((line * 2 - ascent - descent) / 2).rounded(.down)
        return (height - line) / 2 + (ascent + halfLeading) / 2
    }

    static func baseline(top: CGFloat, height: CGFloat, font: NSFont, lineHeight: CGFloat? = nil) -> CGFloat {
        snap(top + baselineOffset(height: height, font: font, lineHeight: lineHeight))
    }

    @discardableResult
    static func draw(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left, truncates: Bool = true) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        var line = self.line(string, font: font)
        var width = self.width(of: line)
        if truncates, rect.width > 0, width > rect.width + 0.25 {
            if let cut = CTLineCreateTruncatedLine(line, Double(rect.width), .end, self.line("\u{2026}", font: font)) {
                line = cut
                width = self.width(of: line)
            }
        }
        var x = rect.minX
        if alignment == .center {
            x = rect.minX + (rect.width - width) / 2
        } else if alignment == .right {
            x = rect.maxX - width
        }
        draw(line, x: x, top: rect.minY, height: rect.height, font: font, color: color)
        return width
    }

    static func draw(_ line: CTLine, x: CGFloat, top: CGFloat, height: CGFloat, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil) {
        guard let current = NSGraphicsContext.current else { return }
        let context = current.cgContext
        let offset = baselineOffset(height: height, font: font, lineHeight: lineHeight)
        context.saveGState()
        context.setShouldSmoothFonts(false)
        color.setFill()
        if current.isFlipped {
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: snap(x), y: snap(top + offset))
        } else {
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: snap(x), y: snap(top + height - offset))
        }
        CTLineDraw(line, context)
        context.restoreGState()
    }

    static func wrap(_ string: String, font: NSFont, width: CGFloat, maxLines: Int = 0) -> [CTLine] {
        guard !string.isEmpty else { return [] }
        let text = attributed(string, font: font)
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        let length = text.length
        var lines: [CTLine] = []
        var start = 0
        while start < length {
            if maxLines > 0, lines.count == maxLines - 1 {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length - start))
                if self.width(of: rest) > width + 0.25, let cut = CTLineCreateTruncatedLine(rest, Double(max(width, 1)), .end, line("\u{2026}", font: font)) {
                    lines.append(cut)
                } else {
                    lines.append(rest)
                }
                break
            }
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(max(width, 1))), 1)
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }
}
