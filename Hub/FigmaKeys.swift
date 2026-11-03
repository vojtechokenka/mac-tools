import AppKit
import Carbon.HIToolbox

final class FigmaPivotKey {
    private static let bundleID = "com.figma.Desktop"
    private static let menuTitle = "Plugins"
    private static let itemTitle = "Nastavit pivot"
    private var tap: CFMachPort?
    private var trustPoll: Timer?
    private var activation: NSObjectProtocol?
    private var figmaActive = false

    func installWhenTrusted() {
        if AXIsProcessTrusted() {
            install()
            return
        }
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustPoll = nil
            self?.install()
        }
    }

    private func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let key = Unmanaged<FigmaPivotKey>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = key.tap { CGEvent.tapEnable(tap: tap, enable: key.figmaActive) }
                return Unmanaged.passUnretained(event)
            }
            return key.handle(event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("could not create event tap for Figma ⌘E")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFigmaActive(app?.bundleIdentifier == Self.bundleID)
        }
        setFigmaActive(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID)
        log("Figma ⌘E opens Pivot")
    }

    private func setFigmaActive(_ active: Bool) {
        figmaActive = active
        if let tap { CGEvent.tapEnable(tap: tap, enable: active) }
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard figmaActive, event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_E) else { return false }
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard modifiers == .maskCommand else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            DispatchQueue.main.async { Self.pressPivot(pid: pid) }
        }
        return true
    }

    private static func pressPivot(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        guard let menuBar = attribute(app, kAXMenuBarAttribute).map({ $0 as! AXUIElement }),
              let plugins = children(menuBar).first(where: { title($0) == menuTitle }),
              let item = find(itemTitle, in: plugins, depth: 6) else {
            log("Figma menu item \(itemTitle) not found")
            return
        }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func title(_ element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute) as? String
    }

    private static func find(_ wanted: String, in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth > 0 else { return nil }
        for child in children(element) {
            if title(child) == wanted { return child }
            if let found = find(wanted, in: child, depth: depth - 1) { return found }
        }
        return nil
    }
}
