// Exhibit Maker — data model: the exhibit list, settings, labels and Bates math.
import AppKit
import PDFKit
import UniformTypeIdentifiers
import SwiftUI

enum LabelStyle: String, CaseIterable, Identifiable {
    case numbers, letters
    var id: String { rawValue }
    var title: String { self == .numbers ? "1, 2, 3" : "A, B, C" }
}

struct ExhibitItem: Identifiable {
    let id = UUID()
    let url: URL
    var description: String
    let pageCount: Int
}

final class ExhibitModel: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var items: [ExhibitItem] = []
    @Published var isWorking = false
    @Published var progress: Double = 0
    @Published var status = ""

    // Settings (remembered between launches)
    @Published var labelStyle: LabelStyle { didSet { defaults.set(labelStyle.rawValue, forKey: "labelStyle") } }
    @Published var labelWord: String { didSet { defaults.set(labelWord, forKey: "labelWord") } }
    @Published var startNumber: Int { didSet { defaults.set(startNumber, forKey: "startNumber") } }
    @Published var stampFirstPage: Bool { didSet { defaults.set(stampFirstPage, forKey: "stampFirstPage") } }
    @Published var descriptionOnTabPages: Bool { didSet { defaults.set(descriptionOnTabPages, forKey: "descriptionOnTabPages") } }
    @Published var batesPrefix: String { didSet { defaults.set(batesPrefix, forKey: "batesPrefix") } }
    @Published var batesStart: Int { didSet { defaults.set(batesStart, forKey: "batesStart") } }
    @Published var batesDigits: Int { didSet { defaults.set(batesDigits, forKey: "batesDigits") } }
    @Published var batesOnTabPages: Bool { didSet { defaults.set(batesOnTabPages, forKey: "batesOnTabPages") } }

    init() {
        let defaults = UserDefaults.standard   // local: self isn't ready yet
        defaults.register(defaults: [
            "labelStyle": LabelStyle.numbers.rawValue, "labelWord": "EXHIBIT", "startNumber": 1,
            "stampFirstPage": true, "descriptionOnTabPages": false,
            "batesPrefix": "CITY", "batesStart": 1, "batesDigits": 6, "batesOnTabPages": false,
        ])
        labelStyle = LabelStyle(rawValue: defaults.string(forKey: "labelStyle") ?? "") ?? .numbers
        labelWord = defaults.string(forKey: "labelWord") ?? "EXHIBIT"
        startNumber = max(1, defaults.integer(forKey: "startNumber"))
        stampFirstPage = defaults.bool(forKey: "stampFirstPage")
        descriptionOnTabPages = defaults.bool(forKey: "descriptionOnTabPages")
        batesPrefix = defaults.string(forKey: "batesPrefix") ?? "CITY"
        batesStart = max(0, defaults.integer(forKey: "batesStart"))
        batesDigits = min(10, max(1, defaults.integer(forKey: "batesDigits")))
        batesOnTabPages = defaults.bool(forKey: "batesOnTabPages")
    }

    // MARK: Labels and Bates numbers

    static func letters(_ number: Int) -> String {
        var n = number, result = ""
        while n > 0 {
            n -= 1
            result = String(Character(UnicodeScalar(UInt8(65 + n % 26)))) + result
            n /= 26
        }
        return result
    }

    func labelValue(forNumber n: Int) -> String {
        labelStyle == .numbers ? "\(n)" : ExhibitModel.letters(n)
    }

    /// e.g. "EXHIBIT 3" for the item at `index`.
    func label(at index: Int) -> String {
        let value = labelValue(forNumber: startNumber + index)
        let word = labelWord.trimmingCharacters(in: .whitespaces)
        return word.isEmpty ? value : "\(word) \(value)"
    }

    func label(for item: ExhibitItem) -> String {
        label(at: items.firstIndex(where: { $0.id == item.id }) ?? 0)
    }

    func bates(_ n: Int) -> String {
        batesPrefix + String(format: "%0\(batesDigits)d", n)
    }

    /// Bates range for each exhibit, computed live from page counts and settings.
    func batesRanges() -> [UUID: String] {
        var next = batesStart
        var ranges: [UUID: String] = [:]
        for item in items {
            let first = next
            if batesOnTabPages { next += 1 }
            next += item.pageCount
            let last = next - 1
            if last >= first { ranges[item.id] = first == last ? bates(first) : "\(bates(first)) – \(bates(last))" }
        }
        return ranges
    }

    var totalPages: Int { items.reduce(0) { $0 + $1.pageCount } }

    // MARK: Adding and removing

    func add(_ urls: [URL]) {
        var pdfs: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                pdfs += contents.filter { $0.pathExtension.lowercased() == "pdf" }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else if url.pathExtension.lowercased() == "pdf" {
                pdfs.append(url)
            }
        }
        var skipped: [String] = []
        for url in pdfs {
            guard let doc = PDFDocument(url: url), !doc.isLocked else { skipped.append(url.lastPathComponent); continue }
            items.append(ExhibitItem(url: url, description: url.deletingPathExtension().lastPathComponent,
                                     pageCount: doc.pageCount))
        }
        status = skipped.isEmpty ? "" : "Couldn't open (damaged or password-protected): " + skipped.joined(separator: ", ")
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.add(urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        }
    }

    /// Looks the row up by ID each time, so removing rows while editing can't crash.
    func descriptionBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { self.items.first(where: { $0.id == id })?.description ?? "" },
            set: { newValue in
                if let i = self.items.firstIndex(where: { $0.id == id }) { self.items[i].description = newValue }
            })
    }

    func remove(_ item: ExhibitItem) { items.removeAll { $0.id == item.id } }
    func move(from source: IndexSet, to destination: Int) { items.move(fromOffsets: source, toOffset: destination) }

    // MARK: Panels

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add PDFs"
        panel.allowedContentTypes = [.pdf, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
    }

    func chooseOutputAndCreate() {
        guard !items.isEmpty, !isWorking else { return }
        let panel = NSSavePanel()
        panel.title = "Save Exhibit PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Exhibits.pdf"
        panel.directoryURL = items.first?.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        create(at: url)
    }

    /// Copies a tab-separated exhibit index (pastes cleanly into Word tables or Excel).
    func copyIndex() {
        let ranges = batesRanges()
        var lines = ["Exhibit\tDescription\tBates Range\tPages"]
        for (i, item) in items.enumerated() {
            lines.append("\(label(at: i))\t\(item.description)\t\(ranges[item.id] ?? "")\t\(item.pageCount)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        status = "Exhibit index copied — paste it into Word or Excel."
    }

    // MARK: Creating the PDF

    private func create(at url: URL) {
        let job = RenderJob(
            files: items.map(\.url),
            labels: items.indices.map { label(at: $0) },
            descriptions: items.map(\.description),
            stampFirstPage: stampFirstPage,
            descriptionOnTabPages: descriptionOnTabPages,
            batesOnTabPages: batesOnTabPages,
            batesStart: batesStart,
            bates: { [prefix = batesPrefix, digits = batesDigits] n in prefix + String(format: "%0\(digits)d", n) })
        isWorking = true
        progress = 0
        status = "Creating…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ExhibitRenderer().render(job, to: url) { p in
                DispatchQueue.main.async { self.progress = p }
            } }
            DispatchQueue.main.async {
                self.isWorking = false
                switch result {
                case .success(let pages):
                    self.status = "Saved \(url.lastPathComponent) (\(pages) pages)."
                    NSWorkspace.shared.open(url)
                case .failure(let error):
                    self.status = ""
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
}
