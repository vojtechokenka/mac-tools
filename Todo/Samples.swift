import AppKit

enum SnapshotSamples {
    static func document(today: Day) -> Document {
        var document = Document()
        func task(_ source: String, in days: Int?) -> TodoItem {
            TodoItem(source: source, due: days.map { today.adding(days: $0) })
        }
        var renewed = TodoItem(text: "Renew the domain")
        renewed.setDone(true, now: Date())
        document.tasks = [
            task("Website; Plan the case study photos", in: 12),
            task("Studio; Book the photographer", in: 3),
            task("Website; Send the final copy to the client", in: -2),
            task("Buy a monitor arm", in: nil),
            task("Website; Check the homepage on mobile", in: 0),
            task("Studio; Order new fabric samples", in: 1),
            renewed,
            task("Website; Rewrite the pricing page copy so it explains all three packages without any jargon", in: 5),
        ]
        return document
    }

    static func longDocument(today: Day) -> Document {
        var document = Document()
        let projects = ["Website", "Studio", "Home", nil]
        document.tasks = (1...30).map { index in
            let project = projects[index % projects.count]
            let source = (project.map { $0 + "; " } ?? "") + "Sample task number \(index)"
            return TodoItem(source: source, due: index % 3 == 0 ? today.adding(days: index % 7 - 2) : nil)
        }
        return document
    }

    static func controller(_ document: Document, grouped: Bool = true, options: Bool = false) -> PanelController {
        let controller = PanelController(store: TaskStore(sample: document), sortOrder: .deadline, grouped: grouped)
        if options { controller.setOptionsOpen(true) }
        return controller
    }

    static func writeAll(to directory: URL) -> Bool {
        let today = Day.today
        let sample = document(today: today)
        var shots: [(String, () -> NSView)] = []
        shots.append(("todo", {
            let controller = controller(sample)
            controller.previewRow("Order new fabric samples")?.showEditPreview()
            return controller.view
        }))
        shots.append(("todo-options", {
            let controller = controller(sample, options: true)
            return controller.view
        }))
        shots.append(("todo-ungrouped", {
            let controller = controller(sample, grouped: false, options: true)
            return controller.view
        }))
        shots.append(("todo-hover", {
            let controller = controller(sample, grouped: false)
            controller.previewRow("Send the final copy to the client")?.previewHover = true
            return controller.view
        }))
        shots.append(("todo-hover-grouped", {
            let controller = controller(sample)
            controller.previewRow("Check the homepage on mobile")?.previewHover = true
            return controller.view
        }))
        shots.append(("todo-pending", {
            let controller = controller(sample)
            controller.inputField.stringValue = "Studio; Call the printer"
            controller.setPendingDue(today.adding(days: 2), focus: false)
            return controller.view
        }))
        shots.append(("todo-empty", {
            controller(Document()).view
        }))
        shots.append(("todo-long", {
            controller(longDocument(today: today)).view
        }))
        var ok = true
        for (name, build) in shots {
            for dark in [false, true] {
                let file = directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                if !DSSnapshot.write(view: build(), to: file, dark: dark, panel: true) { ok = false }
            }
        }
        for dark in [false, true] {
            let picker = controller(sample).datePickerView
            let file = directory.appendingPathComponent("todo-deadline-\(dark ? "dark" : "light").png")
            if !DSSnapshot.write(view: picker, to: file, dark: dark) { ok = false }
        }
        return ok
    }
}
