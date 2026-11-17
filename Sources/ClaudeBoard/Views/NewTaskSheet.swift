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
        VStack(alignment: .leading, spacing: 16) {
            Text("New task").font(Studio.display(22)).foregroundStyle(Studio.ink)

            VStack(alignment: .leading, spacing: 6) {
                Text("What has to be done?").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                TextField("", text: $title, prompt: Text("Pick an image CDN for product photos"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Studio.display(18, .bold))
                    .lineLimit(1...3)
                    .focused($titleFocused)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                    ProjectMenu(selection: $projectID)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Studio.well))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                    PillTabs(selection: $status, items: [(.backlog, "Backlog"), (.todo, "To do"), (.inProgress, "In progress")], size: 12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Priority").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                PillTabs(selection: $priority, items: [(.none, "None"), (.low, "Low"), (.medium, "Medium"), (.high, "High"), (.urgent, "Urgent")], size: 12)
            }

            HStack(spacing: 12) {
                WellField(title: "Area", text: $area, prompt: "Frontend, Infra…")
                WellField(title: "Labels", text: $labels, prompt: "images, cdn")
            }

            editor("Details", text: $notes, minHeight: 64)
            editor("Done when (one step per line)", text: $steps, minHeight: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text("Save to").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                HStack(spacing: 8) {
                    if let pid = projectID {
                        ForEach(store.folders(for: pid), id: \.self) { f in
                            choice(.folder(f), "\(Paths.tilde(f)), shared with the repo")
                        }
                    }
                    choice(.local, "Only this Mac")
                }
            }

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.studio(.quiet))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create(start: nil) }
                    .buttonStyle(.studio(.secondary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
                CreateAndStartButton(enabled: valid) { agent in create(start: agent) }
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(width: 640)
        .background(Studio.surface)
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

    private func editor(_ label: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
            TextEditor(text: text)
                .font(Studio.text(13.5, .medium))
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
        }
    }

    private func choice(_ d: TaskDestination, _ label: String) -> some View {
        let on = destination == d
        return Button { destination = d } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                Text(label).lineLimit(1)
            }
            .font(Studio.text(12.5, .bold))
            .foregroundStyle(on ? Studio.ink : Studio.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(on ? Studio.well : .clear))
            .overlay(Capsule().stroke(Studio.line, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help(d == .local ? "Keeps the task in the app on this Mac" : "A Markdown file in the backlog folder, which your team and your agents can read")
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && projectID != nil }

    private func create(start agent: Agent?) {
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
        if let agent, let t { store.start(t.id, with: agent) }
        store.showInspector = true
        store.newTaskProject = nil
        dismiss()
    }
}

/// "Create and start with Codex ▾": creates the task and hands it to the default agent, or pick another.
struct CreateAndStartButton: View {
    @Environment(Store.self) private var store
    var enabled: Bool
    let action: (Agent) -> Void

    var body: some View {
        let agent = store.defaultAgent
        HStack(spacing: 0) {
            Button { action(agent) } label: {
                Text("Create and start with \(agent.title)")
                    .font(Studio.text(13, .bold))
                    .padding(.leading, 15)
                    .padding(.trailing, 8)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .help(agent.runsInTerminal ? "Creates the task and opens \(agent.title) on it in Terminal"
                  : "Creates the task and opens the project in \(agent.title), with the task on the clipboard")
            Rectangle().fill(Studio.onInk.opacity(0.25)).frame(width: 1, height: 18)
            Menu {
                ForEach(Agent.allCases) { a in
                    Button(a.title) { action(a) }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .help("Start with another agent")
        }
        .foregroundStyle(Studio.onInk)
        .tint(Studio.onInk)
        .background(Capsule().fill(Studio.ink))
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}
