import AppKit

enum DSIcon: String, CaseIterable {
    case contrast
    case coffee
    case volumeUp
    case timer
    case calendarToday
    case edit
    case close
    case sort
    case replay
    case delete
    case check
    case image
    case description

    var pathData: String {
        switch self {
        case .contrast: return "M324-111.5Q251-143 197-197t-85.5-127Q80-397 80-480t31.5-156Q143-709 197-763t127-85.5Q397-880 480-880t156 31.5Q709-817 763-763t85.5 127Q880-563 880-480t-31.5 156Q817-251 763-197t-127 85.5Q563-80 480-80t-156-31.5ZM520-163q119-15 199.5-104.5T800-480q0-123-80.5-212.5T520-797v634Z"
        case .coffee: return "M440-240q-117 0-198.5-81.5T160-520v-240q0-33 23.5-56.5T240-840h500q58 0 99 41t41 99q0 58-41 99t-99 41h-20v40q0 117-81.5 198.5T440-240ZM240-640h400v-120H240v120Zm480 0h20q25 0 42.5-17.5T800-700q0-25-17.5-42.5T740-760h-20v120ZM160-120v-80h640v80H160Z"
        case .volumeUp: return "M560-131v-82q90-26 145-100t55-168q0-94-55-168T560-749v-82q124 28 202 125.5T840-481q0 127-78 224.5T560-131ZM120-360v-240h160l200-200v640L280-360H120Zm440 40v-322q47 22 73.5 66t26.5 96q0 51-26.5 94.5T560-320Z"
        case .timer: return "M360-840v-80h240v80H360Zm80 440h80v-240h-80v240Zm-99.5 291.5Q275-137 226-186t-77.5-114.5Q120-366 120-440t28.5-139.5Q177-645 226-694t114.5-77.5Q406-800 480-800q62 0 119 20t107 58l56-56 56 56-56 56q38 50 58 107t20 119q0 74-28.5 139.5T734-186q-49 49-114.5 77.5T480-80q-74 0-139.5-28.5Z"
        case .calendarToday: return "M200-80q-33 0-56.5-23.5T120-160v-560q0-33 23.5-56.5T200-800h40v-80h80v80h320v-80h80v80h40q33 0 56.5 23.5T840-720v560q0 33-23.5 56.5T760-80H200Zm0-80h560v-400H200v400Z"
        case .edit: return "M120-120v-170l528-527q12-11 26.5-17t30.5-6q16 0 31 6t26 18l55 56q12 11 17.5 26t5.5 30q0 16-5.5 30.5T817-647L290-120H120Zm584-528 56-56-56-56-56 56 56 56Z"
        case .close: return "m256-200-56-56 224-224-224-224 56-56 224 224 224-224 56 56-224 224 224 224-56 56-224-224-224 224Z"
        case .sort: return "M120-240v-80h240v80H120Zm0-200v-80h480v80H120Zm0-200v-80h720v80H120Z"
        case .replay: return "M339.5-108.5q-65.5-28.5-114-77t-77-114Q120-365 120-440h80q0 117 81.5 198.5T480-160q117 0 198.5-81.5T760-440q0-117-81.5-198.5T480-720h-6l62 62-56 58-160-160 160-160 56 58-62 62h6q75 0 140.5 28.5t114 77q48.5 48.5 77 114T840-440q0 75-28.5 140.5t-77 114q-48.5 48.5-114 77T480-80q-75 0-140.5-28.5Z"
        case .delete: return "M280-120q-33 0-56.5-23.5T200-200v-520h-40v-80h200v-40h240v40h200v80h-40v520q0 33-23.5 56.5T680-120H280Zm80-160h80v-360h-80v360Zm160 0h80v-360h-80v360Z"
        case .check: return "M382-240 154-468l57-57 171 171 367-367 57 57-424 424Z"
        case .image: return "M200-120q-33 0-56.5-23.5T120-200v-560q0-33 23.5-56.5T200-840h560q33 0 56.5 23.5T840-760v560q0 33-23.5 56.5T760-120H200Zm40-160h480L570-480 450-320l-90-120-120 160Z"
        case .description: return "M320-240h320v-80H320v80Zm0-160h320v-80H320v80ZM240-80q-33 0-56.5-23.5T160-160v-640q0-33 23.5-56.5T240-880h320l240 240v480q0 33-23.5 56.5T720-80H240Zm280-520h200L520-800v200Z"
        }
    }

    var opticalScale: CGFloat {
        switch self {
        case .close: return 1.14
        case .replay: return 0.9
        default: return 1
        }
    }

    var accessibilityName: String {
        switch self {
        case .contrast: return "Brightness"
        case .coffee: return "Stay awake"
        case .volumeUp: return "Audio"
        case .timer: return "Timer"
        case .calendarToday: return "Date"
        case .edit: return "Edit"
        case .close: return "Close"
        case .sort: return "Sort"
        case .replay: return "Replace"
        case .delete: return "Delete"
        case .check: return "Done"
        case .image: return "Image"
        case .description: return "Document"
        }
    }

    private static var pathCache: [DSIcon: CGPath] = [:]
    private static var templateCache: [String: NSImage] = [:]

    var path: CGPath {
        if let cached = Self.pathCache[self] { return cached }
        let parsed = DSIconPath.parse(pathData)
        Self.pathCache[self] = parsed
        return parsed
    }

    func draw(in rect: NSRect, color: NSColor, opacity: CGFloat = 1) {
        guard let current = NSGraphicsContext.current else { return }
        let context = current.cgContext
        let scale = min(rect.width, rect.height) / 960 * opticalScale
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: current.isFlipped ? scale : -scale)
        context.translateBy(x: -480, y: -480)
        context.addPath(path)
        if opacity < 1 { context.setAlpha(opacity) }
        color.setFill()
        context.fillPath()
        context.restoreGState()
    }

    func image(size: CGFloat = DS.iconSize) -> NSImage {
        let key = "\(rawValue)@\(size)"
        if let cached = Self.templateCache[key] { return cached }
        let icon = self
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            icon.draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityName
        Self.templateCache[key] = image
        return image
    }

    func image(size: CGFloat = DS.iconSize, color: NSColor, opacity: CGFloat = 1) -> NSImage {
        let icon = self
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            icon.draw(in: rect, color: color, opacity: opacity)
            return true
        }
        image.accessibilityDescription = accessibilityName
        return image
    }
}

enum DSIconPath {
    static func parse(_ data: String) -> CGPath {
        let scalars = Array(data.unicodeScalars)
        let count = scalars.count
        let path = CGMutablePath()
        var index = 0
        var command: Unicode.Scalar = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var quadControl: CGPoint?
        var cubicControl: CGPoint?

        func skipSeparators() {
            while index < count, scalars[index] == " " || scalars[index] == "," || scalars[index] == "\n" { index += 1 }
        }

        func hasNumber() -> Bool {
            skipSeparators()
            guard index < count else { return false }
            let scalar = scalars[index]
            return scalar == "-" || scalar == "+" || scalar == "." || (scalar >= "0" && scalar <= "9")
        }

        func number() -> CGFloat {
            skipSeparators()
            let begin = index
            if index < count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
            var seenDot = false
            while index < count {
                let scalar = scalars[index]
                if scalar >= "0" && scalar <= "9" {
                    index += 1
                } else if scalar == "." && !seenDot {
                    seenDot = true
                    index += 1
                } else {
                    break
                }
            }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: scalars[begin..<index])
            return CGFloat(Double(String(text)) ?? 0)
        }

        func point(relative: Bool) -> CGPoint {
            let x = number()
            let y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skipSeparators()
            guard index < count else { break }
            let scalar = scalars[index]
            let isLetter = (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
            if isLetter {
                command = scalar
                index += 1
            } else if !hasNumber() || command == "Z" || command == "z" {
                index += 1
                continue
            } else if command == "M" {
                command = "L"
            } else if command == "m" {
                command = "l"
            }
            let relative = command.value >= 97
            switch command {
            case "M", "m":
                guard hasNumber() else { continue }
                current = point(relative: relative)
                start = current
                path.move(to: current)
                quadControl = nil
                cubicControl = nil
            case "L", "l":
                guard hasNumber() else { continue }
                current = point(relative: relative)
                path.addLine(to: current)
                quadControl = nil
                cubicControl = nil
            case "H", "h":
                guard hasNumber() else { continue }
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                quadControl = nil
                cubicControl = nil
            case "V", "v":
                guard hasNumber() else { continue }
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                quadControl = nil
                cubicControl = nil
            case "Q", "q":
                guard hasNumber() else { continue }
                let control = point(relative: relative)
                let end = point(relative: relative)
                path.addQuadCurve(to: end, control: control)
                quadControl = control
                cubicControl = nil
                current = end
            case "T", "t":
                guard hasNumber() else { continue }
                let control = quadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(relative: relative)
                path.addQuadCurve(to: end, control: control)
                quadControl = control
                cubicControl = nil
                current = end
            case "C", "c":
                guard hasNumber() else { continue }
                let first = point(relative: relative)
                let second = point(relative: relative)
                let end = point(relative: relative)
                path.addCurve(to: end, control1: first, control2: second)
                cubicControl = second
                quadControl = nil
                current = end
            case "S", "s":
                guard hasNumber() else { continue }
                let first = cubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let second = point(relative: relative)
                let end = point(relative: relative)
                path.addCurve(to: end, control1: first, control2: second)
                cubicControl = second
                quadControl = nil
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = start
                quadControl = nil
                cubicControl = nil
            default:
                if hasNumber() { _ = number() }
            }
        }
        var shift = CGAffineTransform(translationX: 0, y: 960)
        return path.copy(using: &shift) ?? path
    }
}
