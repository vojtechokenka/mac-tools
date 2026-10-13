import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[Todo] " + message + "\n").utf8))
}

enum Section: String, CaseIterable {
    case tasks = "Tasks"
    case archive = "Archive"

    var heading: String { "## " + rawValue }
}

enum HideDoneMode: String {
    case immediately
    case after24h

    static let defaultsKey = "hideDoneMode"

    var threshold: TimeInterval { self == .immediately ? 0 : 24 * 3600 }
}

struct Day: Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static let distantFuture = Day(year: 9999, month: 12, day: 31)

    private static let isoPattern = #/^(\d{4})-(\d{2})-(\d{2})$/#

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date) {
        let parts = Day.calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    init?(iso: String) {
        guard let match = iso.wholeMatch(of: Day.isoPattern),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
              Day.isValid(year: year, month: month, day: day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    static var today: Day { Day(Date()) }

    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var parts = DateComponents(year: year, month: month, day: day)
        parts.calendar = calendar
        return parts.isValidDate
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var shortLabel: String { "\(day). \(month)." }
    var fullLabel: String { "\(DateInput.fullAbbreviations[mondayIndex]) \(day) \(DateInput.monthNames[month - 1]) \(year)" }

    var components: DateComponents { DateComponents(year: year, month: month, day: day) }

    var date: Date {
        Day.calendar.date(from: components) ?? Date()
    }

    var mondayIndex: Int {
        (Day.calendar.component(.weekday, from: date) + 5) % 7
    }

    func adding(days: Int) -> Day {
        Day(Day.calendar.date(byAdding: .day, value: days, to: date) ?? date)
    }

    func days(until other: Day) -> Int {
        Day.calendar.dateComponents([.day], from: components, to: other.components).day ?? 0
    }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct Stamp: Equatable {
    var day: Day
    var minuteOfDay: Int?

    private static let pattern = #/^(\d{4}-\d{2}-\d{2})(?:T(\d{2}):(\d{2}))?$/#

    init(day: Day, minuteOfDay: Int? = nil) {
        self.day = day
        self.minuteOfDay = minuteOfDay
    }

    init(_ date: Date) {
        day = Day(date)
        let parts = Day.calendar.dateComponents([.hour, .minute], from: date)
        minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    init?(iso: String) {
        guard let match = iso.wholeMatch(of: Stamp.pattern), let day = Day(iso: String(match.1)) else { return nil }
        if let hourText = match.2, let minuteText = match.3 {
            guard let hour = Int(hourText), let minute = Int(minuteText), hour < 24, minute < 60 else { return nil }
            self.init(day: day, minuteOfDay: hour * 60 + minute)
        } else {
            self.init(day: day)
        }
    }

    var iso: String {
        guard let minuteOfDay else { return day.iso }
        return day.iso + String(format: "T%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    var date: Date? {
        guard let minuteOfDay else { return nil }
        var parts = day.components
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        return Day.calendar.date(from: parts)
    }

    func isExpired(now: Date, threshold: TimeInterval) -> Bool {
        if threshold <= 0 { return true }
        if let date { return now.timeIntervalSince(date) >= threshold }
        return day < Day(now)
    }
}

struct TodoItem: Equatable {
    var project: String?
    var text: String
    var done = false
    var due: Day?
    var completed: Stamp?

    static let maxProjectLength = 40

    private static let linePattern = #/^\s*[-*+]\s*\[\s*([xX ]?)\s*\]\s*(.*?)\s*$/#
    private static let plainPattern = #/^\s*[-*+]\s+(.*?)\s*$/#
    private static let duePattern = #/^(.*\S)\s+@(\d{4}-\d{2}-\d{2})$/#
    private static let completedPattern = #/^(.*\S)\s+✓(\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2})?)$/#

    init(project: String? = nil, text: String, done: Bool = false, due: Day? = nil, completed: Stamp? = nil) {
        self.project = project
        self.text = text
        self.done = done
        self.due = due
        self.completed = completed
    }

    init(source: String, due: Day? = nil) {
        var item = TodoItem(text: source.trimmingCharacters(in: .whitespacesAndNewlines), due: due)
        while let parsed = TodoItem.parse(line: item.line), parsed != item {
            item = TodoItem(project: parsed.project, text: parsed.text, due: due ?? parsed.due)
        }
        self = item
    }

    var source: String { project.map { $0 + "; " + text } ?? text }
    var projectKey: String? { project?.lowercased() }

    var line: String {
        var result = "- [\(done ? "x" : " ")] " + source
        if let due { result += " @" + due.iso }
        if let completed { result += " ✓" + completed.iso }
        return result
    }

    mutating func setDone(_ value: Bool, now: Date) {
        done = value
        completed = value ? Stamp(now) : nil
    }

    static func splitSource(_ source: String) -> (project: String?, text: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "; ") else { return (nil, trimmed) }
        let project = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let text = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !project.isEmpty, project.count <= maxProjectLength, !text.isEmpty else { return (nil, trimmed) }
        return (project, text)
    }

    static func parse(line: String) -> TodoItem? {
        var item: TodoItem
        if let match = line.wholeMatch(of: linePattern) {
            item = TodoItem(text: String(match.2), done: match.1.lowercased() == "x")
        } else if let match = line.wholeMatch(of: plainPattern) {
            item = TodoItem(text: String(match.1))
        } else {
            return nil
        }
        guard !item.text.isEmpty else { return nil }
        var stripped = true
        while stripped {
            stripped = false
            if item.completed == nil, let tail = item.text.wholeMatch(of: completedPattern), let stamp = Stamp(iso: String(tail.2)) {
                item.completed = stamp
                item.text = String(tail.1)
                stripped = true
            } else if item.due == nil, let tail = item.text.wholeMatch(of: duePattern), let day = Day(iso: String(tail.2)) {
                item.due = day
                item.text = String(tail.1)
                stripped = true
            }
        }
        let parts = splitSource(item.text)
        item.project = parts.project
        item.text = parts.text
        return item
    }
}

struct TaskRef {
    var section: Section
    var item: TodoItem
    var occurrence: Int
}

struct TaskGroup: Equatable {
    var title: String
    var key: String?
    var indices: [Int]
    var openCount: Int
}

struct Document: Equatable {
    static let noProjectTitle = "No project"
    private static let collationLocale = Locale(identifier: "en_GB")

    var preamble = "# Tasks"
    var tasks: [TodoItem] = []
    var archive: [TodoItem] = []
    var notes: [Section: [String]] = [:]
    var extras: [Section: [String]] = [:]

    subscript(section: Section) -> [TodoItem] {
        get {
            switch section {
            case .tasks: return tasks
            case .archive: return archive
            }
        }
        set {
            switch section {
            case .tasks: tasks = newValue
            case .archive: archive = newValue
            }
        }
    }

    func dueCount(today: Day) -> Int {
        tasks.filter { !$0.done }.count
    }

    var projectNames: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for item in tasks + archive {
            guard let project = item.project, let key = item.projectKey, !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(project)
        }
        return names
    }

    func ref(_ section: Section, _ index: Int) -> TaskRef {
        let item = self[section][index]
        return TaskRef(section: section, item: item, occurrence: self[section][..<index].filter { $0 == item }.count)
    }

    func index(of ref: TaskRef) -> Int? {
        let items = self[ref.section]
        let matches = items.indices.filter { items[$0] == ref.item }
        return matches.indices.contains(ref.occurrence) ? matches[ref.occurrence] : matches.first
    }

    private func sortedIndices(_ indices: [Int]) -> [Int] {
        indices.sorted { lhs, rhs in
            let a = tasks[lhs], b = tasks[rhs]
            if a.done != b.done { return !a.done }
            let dueA = a.due ?? .distantFuture, dueB = b.due ?? .distantFuture
            if dueA != dueB { return dueA < dueB }
            return lhs < rhs
        }
    }

    func groups() -> [TaskGroup] {
        var titles: [String: String] = [:]
        var members: [String: [Int]] = [:]
        var loose: [Int] = []
        for (index, item) in tasks.enumerated() {
            if let project = item.project, let key = item.projectKey {
                if titles[key] == nil { titles[key] = project }
                members[key, default: []].append(index)
            } else {
                loose.append(index)
            }
        }
        var groups = members.map { key, indices in
            TaskGroup(title: titles[key] ?? key, key: key, indices: sortedIndices(indices), openCount: indices.filter { !tasks[$0].done }.count)
        }
        groups.sort { lhs, rhs in
            let order = lhs.title.compare(rhs.title, options: [.caseInsensitive], range: nil, locale: Document.collationLocale)
            return order == .orderedSame ? (lhs.key ?? "") < (rhs.key ?? "") : order == .orderedAscending
        }
        if !loose.isEmpty {
            groups.append(TaskGroup(title: Document.noProjectTitle, key: nil, indices: sortedIndices(loose), openCount: loose.filter { !tasks[$0].done }.count))
        }
        return groups
    }

    mutating func sweep(now: Date, threshold: TimeInterval) {
        var remaining: [TodoItem] = []
        for var item in tasks {
            guard item.done else { remaining.append(item); continue }
            let stamp = item.completed ?? Stamp(now)
            item.completed = stamp
            if stamp.isExpired(now: now, threshold: threshold) {
                archive.append(item)
            } else {
                remaining.append(item)
            }
        }
        tasks = remaining
    }

    private static func trimmingTrailingWhitespace(_ lines: [String]) -> String {
        String(lines.joined(separator: "\n").reversed().drop(while: { $0.isWhitespace || $0.isNewline }).reversed())
    }

    static func parse(_ text: String) -> Document {
        let headings: [String: (section: Section, legacy: Int?)] = [
            "## Tasks": (.tasks, nil), "## Archive": (.archive, nil),
            "## Úkoly": (.tasks, nil), "## Archiv": (.archive, nil),
            "## Dnes": (.tasks, 0), "## Později": (.tasks, 1),
        ]
        var document = Document()
        var preambleLines: [String] = []
        var legacy: [[TodoItem]] = [[], []]
        var migrated = false
        var legacyHeadingSeen = false
        var current: (section: Section, legacy: Int?)?
        var inUnknownBlock = false
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let target = headings[trimmed] {
                if target.legacy != nil { migrated = true }
                if trimmed == "## Úkoly" || trimmed == "## Archiv" { legacyHeadingSeen = true }
                current = target
                inUnknownBlock = false
                continue
            }
            guard let current else {
                preambleLines.append(line)
                continue
            }
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                inUnknownBlock = true
                log("unknown section preserved unchanged: \(trimmed)")
            }
            if inUnknownBlock {
                document.extras[current.section, default: []].append(line)
                continue
            }
            if let item = TodoItem.parse(line: line) {
                if let slot = current.legacy {
                    legacy[slot].append(item)
                } else {
                    document[current.section].append(item)
                }
            } else if !trimmed.isEmpty {
                document.notes[current.section, default: []].append(line)
                log("unknown line in section \(current.section.rawValue) preserved after tasks: \(line)")
            }
        }
        document.tasks += legacy[0] + legacy[1]
        for (section, block) in document.extras {
            document.extras[section] = Array(block.reversed().drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty }).reversed())
        }
        if migrated { log("legacy Dnes/Později format loaded into the Tasks section, the file will be converted on the next write") }
        document.preamble = trimmingTrailingWhitespace(preambleLines)
        if legacyHeadingSeen { log("legacy Czech headings loaded, the file will be converted on the next write") }
        if document.preamble == "# Úkoly" { document.preamble = "# Tasks" }
        if document.preamble.isEmpty, current == nil { document.preamble = "# Tasks" }
        return document
    }

    var serialized: String {
        var out = preamble.isEmpty ? "" : preamble + "\n\n"
        for (index, section) in Section.allCases.enumerated() {
            out += section.heading + "\n"
            for item in self[section] { out += item.line + "\n" }
            for line in notes[section] ?? [] { out += line + "\n" }
            if let block = extras[section], !block.isEmpty { out += "\n" + block.joined(separator: "\n") + "\n" }
            if index < Section.allCases.count - 1 { out += "\n" }
        }
        return out
    }
}

enum DateInput {
    static let fullAbbreviations = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let weekdayNames = [
        ["mon", "monday"], ["tue", "tuesday"], ["wed", "wednesday"], ["thu", "thursday"],
        ["fri", "friday"], ["sat", "saturday"], ["sun", "sunday"],
    ]
    private static let numericPattern = #/^(\d{1,2})\.(\d{1,2})\.(\d{4})?$/#

    static func parseToken(_ token: String, today: Day) -> Day? {
        let lowered = token.lowercased()
        switch lowered {
        case "today": return today
        case "tomorrow": return today.adding(days: 1)
        default: break
        }
        if let index = weekdayNames.firstIndex(where: { $0.contains(lowered) }) {
            return today.adding(days: (index - today.mondayIndex + 7) % 7)
        }
        if lowered.hasPrefix("@"), let day = Day(iso: String(lowered.dropFirst())) {
            return day
        }
        if let match = lowered.wholeMatch(of: numericPattern), let day = Int(match.1), let month = Int(match.2) {
            if let yearText = match.3, let year = Int(yearText) {
                return Day.isValid(year: year, month: month, day: day) ? Day(year: year, month: month, day: day) : nil
            }
            guard Day.isValid(year: today.year, month: month, day: day) else { return nil }
            let candidate = Day(year: today.year, month: month, day: day)
            if candidate >= today { return candidate }
            return Day.isValid(year: today.year + 1, month: month, day: day) ? Day(year: today.year + 1, month: month, day: day) : candidate
        }
        return nil
    }

    static func split(_ input: String, today: Day) -> (text: String, due: Day?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cut = trimmed.lastIndex(where: { $0.isWhitespace }) else { return (trimmed, nil) }
        let token = String(trimmed[trimmed.index(after: cut)...])
        let text = trimmed[..<cut].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let due = parseToken(token, today: today) else { return (trimmed, nil) }
        return (text, due)
    }

    static func countdown(due: Day?, today: Day) -> (text: String, urgency: Int) {
        guard let due else { return ("", 0) }
        let days = today.days(until: due)
        switch days {
        case 0: return ("Today", 2)
        case 1: return ("Tomorrow", 2)
        case 2...3: return ("\(days) days", 1)
        case 4...: return ("\(days) days", 0)
        case -1: return ("1 day ago", 2)
        default: return ("\(-days) days ago", 2)
        }
    }
}

final class TaskStore {
    let path: String
    private(set) var document = Document()
    var onExternalChange: (() -> Void)?
    var onWillReload: (() -> Void)?
    private var readFailed = false
    private var lastModified: Date?
    private var lastContent = ""
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var pendingCheck: DispatchWorkItem?

    init(path: String) {
        self.path = path
    }

    func load() {
        guard FileManager.default.fileExists(atPath: path) else {
            document = Document()
            write()
            log("created new task file \(path)")
            return
        }
        readFromDisk()
    }

    @discardableResult
    func mutate(_ change: (inout Document) -> Void) -> Bool {
        if diskChanged() {
            log("file changed externally, reloading before write")
            readFromDisk()
        }
        guard !readFailed else {
            log("task file cannot be read, write blocked")
            return false
        }
        var updated = document
        change(&updated)
        guard updated != document else { return true }
        document = updated
        write()
        return true
    }

    func checkForExternalChange() {
        guard diskChanged() else { return }
        log("task file changed externally, reloading")
        onWillReload?()
        readFromDisk()
        if !readFailed { onExternalChange?() }
    }

    func startWatching() {
        let directory = (path as NSString).deletingLastPathComponent
        let descriptor = open(directory, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleCheck() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            directorySource = source
        } else {
            log("directory watch failed (errno \(errno))")
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.checkForExternalChange() }
        timer.resume()
        pollTimer = timer
    }

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.checkForExternalChange() }
        pendingCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func diskChanged() -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let modified = modificationDate()
        if modified == lastModified { return false }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return true }
        if content == lastContent {
            lastModified = modified
            return false
        }
        return true
    }

    private func readFromDisk() {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            lastContent = content
            lastModified = modificationDate()
            document = Document.parse(content)
            readFailed = false
        } catch {
            if !readFailed { log("cannot read task file: \(error.localizedDescription)") }
            readFailed = true
        }
    }

    private func write() {
        let content = document.serialized
        let directory = (path as NSString).deletingLastPathComponent
        let temporary = (directory as NSString).appendingPathComponent(".\((path as NSString).lastPathComponent).tmp-\(getpid())")
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try content.write(toFile: temporary, atomically: false, encoding: .utf8)
            guard rename(temporary, path) == 0 else {
                unlink(temporary)
                log("renaming temporary file failed: \(String(cString: strerror(errno)))")
                return
            }
            lastContent = content
            lastModified = modificationDate()
        } catch {
            unlink(temporary)
            log("writing task file failed: \(error.localizedDescription)")
        }
    }
}
