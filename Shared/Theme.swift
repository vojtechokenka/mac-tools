import AppKit
import CoreText

enum DS {
    static let paper = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let sunken = dynamic(light: 0xF3F3F3, dark: 0x161616)
    static let chip = dynamic(light: 0xE6E6E6, dark: 0x262626)
    static let line = dynamic(light: 0xD6D6D6, dark: 0x363636)
    static let muted = dynamic(light: 0x666666, dark: 0x9A9A9A)
    static let ink = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let text = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.84, darkAlpha: 0.84)
    static let icon = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.40, darkAlpha: 0.40)
    static let edge = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.30, darkAlpha: 0.30)
    static let blue = dynamic(light: 0x146EF5, dark: 0x146EF5)
    static let blueText = dynamic(light: 0x146EF5, dark: 0x5C9DFF)
    static let pink = dynamic(light: 0xB53A9A, dark: 0xD457BB)
    static let red = dynamic(light: 0xD3261A, dark: 0xFF6A5C)
    static let onRed = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let amber = dynamic(light: 0xF2A94A, dark: 0xF2A94A)
    static let amberText = dynamic(light: 0xA35A00, dark: 0xF2A94A)

    static let onBlue = rgb(0xFFFFFF)
    static let onAmber = rgb(0x000000)
    static let blueHover = rgb(0x1679FF)
    static let bluePressed = rgb(0x1263DD)
    static let blueGhost = dynamic(light: 0x146EF5, dark: 0x146EF5, lightAlpha: 0.18, darkAlpha: 0.18)
    static let blueWash = dynamic(light: 0x146EF5, dark: 0x146EF5, lightAlpha: 0.08, darkAlpha: 0.08)
    static let pinkGhost = dynamic(light: 0xB53A9A, dark: 0xD457BB, lightAlpha: 0.22, darkAlpha: 0.22)
    static let floatBorder = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.14)
    static let floatShadow = dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.50)

    static let controlHeight: CGFloat = 28
    static let radius: CGFloat = 4
    static let panelRadius: CGFloat = 12
    static let margin: CGFloat = 16
    static let gap: CGFloat = 10
    static let gapTight: CGFloat = 6
    static let gapLoose: CGFloat = 14
    static let rowHeight: CGFloat = 20
    static let sectionTop: CGFloat = 12
    static let sectionBottom: CGFloat = 14
    static let panelInset: CGFloat = 4
    static let iconSize: CGFloat = 18
    static let iconButtonSize: CGFloat = 24
    static let disabledOpacity: CGFloat = 0.4
    static let floatShadowBlur: CGFloat = 32
    static let floatShadowDrop: CGFloat = 12

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        let lightColor = rgb(light, lightAlpha)
        let darkColor = rgb(dark, darkAlpha)
        return NSColor(name: nil) { isDark($0) ? darkColor : lightColor }
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var result = color
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }

    static func alpha(_ color: NSColor, _ alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let base = resolved(color, for: appearance)
            return base.withAlphaComponent(base.alphaComponent * alpha)
        }
    }
}

extension DS {
    private struct FontKey: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let tabular: Bool
    }

    private static var baseDescriptor: CTFontDescriptor?
    private static var registrationAttempted = false
    private static var fontCache: [FontKey: NSFont] = [:]

    static let fontResourceName = "GoogleSansFlex"

    static var usesBundledFont: Bool { baseDescriptor != nil }

    static var bodyFont: NSFont { font(13) }
    static var smallFont: NSFont { font(11) }
    static var titleFont: NSFont { font(16, .medium) }
    static var countFont: NSFont { font(13, .semibold) }

    @discardableResult
    static func registerFonts() -> Bool {
        if baseDescriptor != nil { return true }
        registrationAttempted = true
        guard let url = Bundle.main.url(forResource: fontResourceName, withExtension: "ttf") else { return false }
        return registerFonts(at: url)
    }

    @discardableResult
    static func registerFonts(at url: URL) -> Bool {
        registrationAttempted = true
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descriptors.first else { return false }
        baseDescriptor = first
        fontCache.removeAll()
        return true
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, tabular: Bool = true) -> NSFont {
        if baseDescriptor == nil && !registrationAttempted { registerFonts() }
        let axisWeight = variationWeight(weight)
        let key = FontKey(size: size, weight: axisWeight, tabular: tabular)
        if let cached = fontCache[key] { return cached }
        let font: NSFont
        if let base = baseDescriptor {
            let variation: [NSNumber: CGFloat] = [
                axis("wght"): axisWeight,
                axis("opsz"): min(max(size, 6), 144),
                axis("wdth"): 100,
                axis("ROND"): 0,
                axis("slnt"): 0,
            ]
            var attributes: [CFString: Any] = [kCTFontVariationAttribute: variation]
            if tabular {
                attributes[kCTFontFeatureSettingsAttribute] = [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]]
            }
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
        } else if tabular {
            font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            font = .systemFont(ofSize: size, weight: weight)
        }
        fontCache[key] = font
        return font
    }

    static func variationWeight(_ weight: NSFont.Weight) -> CGFloat {
        let stops: [(NSFont.Weight, CGFloat)] = [
            (.ultraLight, 100), (.thin, 200), (.light, 300), (.regular, 400), (.medium, 500),
            (.semibold, 600), (.bold, 700), (.heavy, 800), (.black, 900),
        ]
        let raw = weight.rawValue
        if raw <= stops[0].0.rawValue { return stops[0].1 }
        for index in 1..<stops.count {
            let lower = stops[index - 1]
            let upper = stops[index]
            if raw <= upper.0.rawValue {
                let span = upper.0.rawValue - lower.0.rawValue
                let progress = span > 0 ? (raw - lower.0.rawValue) / span : 0
                return (lower.1 + (upper.1 - lower.1) * progress).rounded()
            }
        }
        return 900
    }

    private static func axis(_ tag: String) -> NSNumber {
        var value: UInt32 = 0
        for byte in tag.utf8 { value = value << 8 | UInt32(byte) }
        return NSNumber(value: value)
    }
}
