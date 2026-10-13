import AppKit
import IOKit.pwr_mgt

final class KeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private var activityID: IOPMAssertionID = 0
    private var activityTimer: Timer?

    var isHeld: Bool { assertionID != 0 }

    func acquire() -> Bool {
        guard !isHeld else { return true }
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hub: stay awake" as CFString, &id)
        guard status == kIOReturnSuccess else {
            log("IOPMAssertionCreateWithName failed: 0x\(String(UInt32(bitPattern: status), radix: 16))")
            return false
        }
        assertionID = id
        declareActivity()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.declareActivity() }
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
        return true
    }

    func release() {
        activityTimer?.invalidate()
        activityTimer = nil
        if activityID != 0 {
            IOPMAssertionRelease(activityID)
            activityID = 0
        }
        guard isHeld else { return }
        let status = IOPMAssertionRelease(assertionID)
        if status == kIOReturnSuccess {
            log("assertion \(assertionID) released")
        } else {
            log("IOPMAssertionRelease(\(assertionID)) failed: 0x\(String(UInt32(bitPattern: status), radix: 16))")
        }
        assertionID = 0
    }

    private func declareActivity() {
        let status = IOPMAssertionDeclareUserActivity("Hub" as CFString, kIOPMUserActiveLocal, &activityID)
        if status != kIOReturnSuccess {
            log("IOPMAssertionDeclareUserActivity failed: 0x\(String(UInt32(bitPattern: status), radix: 16))")
        }
    }
}

final class AwakeSession {
    static let durationTitles = ["30 minutes", "1 hour", "2 hours", "4 hours", "Unlimited"]
    static let durationMinutes: [Double?] = [30, 60, 120, 240, nil]
    var onChange: (() -> Void)?
    private(set) var active = false
    private(set) var durationIndex: Int?
    private var deadline: Date?
    private let keepAwake = KeepAwake()
    private let defaults = UserDefaults.standard
    private var tickTimer: Timer?
    private var deadlineTimer: Timer?

    func start(index: Int) {
        guard index >= 0, index < Self.durationMinutes.count else { return }
        start(minutes: Self.durationMinutes[index], index: index)
    }

    func start(minutes: Double?, index: Int? = nil) {
        let wasActive = active
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard keepAwake.acquire() else {
            log("stay awake: start failed, could not create assertion")
            return
        }
        active = true
        durationIndex = index
        if let index { defaults.set(index, forKey: "lastDuration") }
        if let minutes {
            let date = Date(timeIntervalSinceNow: minutes * 60)
            deadline = date
            let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            deadlineTimer = timer
            log("stay awake \(wasActive ? "restart" : "start"): \(Int(minutes)) min, ends \(date)")
        } else {
            deadline = nil
            log("stay awake \(wasActive ? "restart" : "start"): unlimited")
        }
        if tickTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }
        onChange?()
    }

    func stop(reason: String) {
        guard active else { return }
        active = false
        durationIndex = nil
        deadline = nil
        tickTimer?.invalidate()
        tickTimer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        keepAwake.release()
        log("stay awake stop: \(reason)")
        onChange?()
    }

    func shutdown() {
        if active { stop(reason: "app quit") }
        keepAwake.release()
    }

    func tick() {
        guard active else { return }
        if let deadline, Date() >= deadline {
            stop(reason: "time expired")
            return
        }
        onChange?()
    }

    func macDidWake() {
        guard active else { return }
        log("stay awake: Mac woke up, checking deadline")
        tick()
    }

    func remainingSeconds() -> Int? {
        guard let deadline else { return nil }
        return max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    var countdownText: String {
        guard active else { return "" }
        if let seconds = remainingSeconds() {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return "unlimited"
    }

    var statusText: String {
        guard active else { return "" }
        if let seconds = remainingSeconds() {
            return seconds >= 3600 ? String(format: " %d:%02d", seconds / 3600, (seconds % 3600) / 60) : " \(max(1, seconds / 60)) min"
        }
        return " ∞"
    }
}
