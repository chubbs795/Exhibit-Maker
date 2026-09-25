// Exhibit Maker — main window (SwiftUI). Uses only @ObservedObject, so it builds
// with any version of Apple's Command Line Tools.
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ExhibitModel

    var body: some View {
        HStack(spacing: 0) {
            exhibitList
            Divider()
            settingsPanel
        }
        .frame(minWidth: 860, minHeight: 500)
        .disabled(model.isWorking)
    }

    // MARK: Left: the exhibits

    private var exhibitList: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drag PDFs or a folder here").font(.title3)
                    Text("They become exhibits in the order shown. Drag rows to reorder.")
                        .foregroundStyle(.secondary)
                    Button("Add PDFs…") { model.chooseFiles() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let ranges = model.batesRanges()
                List {
                    ForEach(model.items) { item in
                        HStack(spacing: 12) {
                            Text(model.label(for: item))
                                .font(.headline)
                                .frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Description", text: model.descriptionBinding(for: item.id))
                                    .textFieldStyle(.plain)
                                Text("\(item.url.lastPathComponent) · \(item.pageCount) page\(item.pageCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(ranges[item.id] ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button { model.remove(item) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this exhibit")
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
            }

            Divider()
            HStack {
                Button("Add PDFs…") { model.chooseFiles() }
                Button("Clear All") { model.items.removeAll() }
                    .disabled(model.items.isEmpty)
                Button("Copy Index") { model.copyIndex() }
                    .disabled(model.items.isEmpty)
                    .help("Copy a table of exhibits, descriptions and Bates ranges")
                Spacer()
                if model.isWorking {
                    ProgressView(value: model.progress).frame(width: 120)
                }
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
        }
        .frame(minWidth: 540)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            model.handleDrop(providers)
            return true
        }
    }

    // MARK: Right: settings

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Exhibit Labels") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Numbering", selection: $model.labelStyle) {
                        ForEach(LabelStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Label word")
                        TextField("EXHIBIT", text: $model.labelWord)
                    }
                    Stepper(value: $model.startNumber, in: 1...702) {
                        Text("Start at \(model.labelValue(forNumber: model.startNumber))")
                    }
                    Toggle("Stamp label on each exhibit's first page", isOn: $model.stampFirstPage)
                    Toggle("Show description on tab pages", isOn: $model.descriptionOnTabPages)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Bates Numbers") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Prefix")
                        TextField("CITY", text: $model.batesPrefix)
                    }
                    HStack {
                        Text("Start at")
                        TextField("1", value: $model.batesStart, format: .number.grouping(.never))
                            .frame(width: 90)
                    }
                    Stepper(value: $model.batesDigits, in: 1...10) {
                        Text("Digits: \(model.batesDigits)")
                    }
                    Toggle("Number the tab pages too", isOn: $model.batesOnTabPages)
                    Text("Example: \(model.bates(model.batesStart))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Text("\(model.items.count) exhibit\(model.items.count == 1 ? "" : "s") · \(model.totalPages) pages")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.chooseOutputAndCreate()
            } label: {
                Text("Create Exhibit PDF…").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.items.isEmpty)
        }
        .padding(16)
        .frame(width: 300)
    }
}
