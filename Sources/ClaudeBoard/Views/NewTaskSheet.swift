import SwiftUI

struct NewTaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var projectID: String?
    @State private var destination: TaskDestination = .local
    @State private var priority: Priority = .none
    @State private var status: TaskStatus = .todo
    @State private var labels = ""
    @State private var area = ""
    @State private var steps = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Task").font(.title3.weight(.semibold)).padding([.horizontal, .top], 20)
            Form {
                TextField("What has to be done?", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($titleFocused)
                LabeledContent("Project") {
                    ProjectMenu(selection: $projectID)
                }
                Picker("Save to", selection: $destination) {
                    if let pid = projectID {
                        ForEach(store.folders(for: pid), id: \.self) { f in
                            Label(Paths.tilde(f), systemImage: "folder").tag(TaskDestination.folder(f))
                        }
                    }
                    Label("This Mac only", systemImage: "laptopcomputer").tag(TaskDestination.local)
                }
                .help("A backlog folder is a set of markdown files your team and Claude can read. 'This Mac only' keeps it in ClaudeBoard.")
                HStack {
                    Picker("Status", selection: $status) {
                        Text("Backlog").tag(TaskStatus.backlog)
                        Text("To Do").tag(TaskStatus.todo)
                        Text("In Progress").tag(TaskStatus.inProgress)
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases.reversed()) { Text($0.title).tag($0) }
                    }
                }
                HStack {
                    TextField("Area", text: $area, prompt: Text("Frontend, Infra…"))
                    TextField("Labels", text: $labels, prompt: Text("bug, auth"))
                }
                Section("Details") {
                    TextEditor(text: $notes).frame(minHeight: 90).font(.callout)
                }
                Section("Done when (one step per line)") {
                    TextEditor(text: $steps).frame(minHeight: 60).font(.callout)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("“Create & Start” opens Terminal and gives the task to Claude Code in the project folder.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create & Start") { create(start: true) }
                    .disabled(!valid)
                Button("Create") { create(start: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
            .padding(16)
        }
        .frame(width: 580, height: 660)
        .onAppear {
            projectID = store.newTaskProject ?? store.scopeProjectID ?? store.lastQuickAddProject
                ?? store.items.first(where: { $0.projectID.hasPrefix("/") })?.projectID
            if let p = projectID { destination = store.defaultDestination(for: p) }
            titleFocused = true
        }
        .onChange(of: projectID) { _, p in
            if let p { destination = store.defaultDestination(for: p) }
        }
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && projectID != nil }

    private func create(start: Bool) {
        guard let pid = projectID else { return }
        let t = store.createTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: pid,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            status: status,
            labels: labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            subtasks: steps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            area: area.trimmingCharacters(in: .whitespaces).isEmpty ? nil : area.trimmingCharacters(in: .whitespaces),
            destination: destination
        )
        if start, let t { store.startWithClaude(t.id) }
        store.showInspector = true
        store.newTaskProject = nil
        dismiss()
    }
}
