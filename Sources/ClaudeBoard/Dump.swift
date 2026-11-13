import Foundation

/// `ClaudeBoard --dump [n]` prints what ingestion sees, for checking it against real data.
enum Dump {
    static func run(limit: Int) {
        let ing = Ingestor()
        let r = ing.run()
        let sessions = Dictionary(uniqueKeysWithValues: r.sessions.map { ($0.id, $0) })
        var all = r.transcriptTasks
        for (_, ts) in r.historyTasks { all.append(contentsOf: ts) }
        var grouped = Dictionary(grouping: all, by: { $0.sessionID ?? "" })
        for (sid, var ts) in grouped {
            Ingestor.inferStatuses(&ts, session: sessions[sid])
            grouped[sid] = ts
        }
        all = grouped.values.flatMap { $0 }

        print(String(format: "ingest: %.2fs, %.1f MB read", r.duration, Double(r.bytesRead) / 1e6))
        print("sessions: \(r.sessions.count) (\(r.transcriptSessionIDs.count) with transcripts, \(r.live.count) live)")
        print("tickets: \(all.count)  prompt=\(all.filter { $0.origin == .prompt }.count) history=\(all.filter { $0.origin == .history }.count) suggested=\(all.filter { $0.origin == .suggested }.count)")
        print("follow-ups folded: \(all.reduce(0) { $0 + $1.followUps.count })")
        print("")
        print("by project:")
        for (pid, ts) in Dictionary(grouping: all, by: \.projectID).sorted(by: { $0.value.count > $1.value.count }) {
            let st = Dictionary(grouping: ts, by: \.inferredStatus).map { "\($0.key.title)=\($0.value.count)" }.sorted().joined(separator: " ")
            print("  \(ts.count)\t\(pid.replacingOccurrences(of: Paths.home, with: "~"))\t\(st)")
        }
        print("")
        print("open tickets:")
        for t in all.filter({ $0.inferredStatus != .done }).sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(limit) {
            let p = t.subtaskProgress
            print("  [\(t.inferredStatus.title)] \(t.title)  (\(p.done)/\(p.total) steps, \(t.followUps.count) follow-ups, \(t.stats.toolCalls) tools)\(t.pendingAsk.map { " ask: \($0)" } ?? "")")
        }
        print("")
        print("latest tickets:")
        for t in all.sorted(by: { $0.createdAt > $1.createdAt }).prefix(limit) {
            print("  \(t.createdAt.formatted(date: .abbreviated, time: .shortened))  [\(t.inferredStatus.title)] \(t.title)")
        }
        print("")
        print("sessions:")
        for s in r.sessions.sorted(by: { $0.lastActivity > $1.lastActivity }) {
            print("  \(s.isLive ? (s.isBusy ? "●" : "○") : " ") \(s.lastActivity.formatted(date: .abbreviated, time: .omitted))  \(s.title)  [\(s.promptCount) prompts]\(s.needsAction.map { " needs: \($0)" } ?? "")")
        }
        // second pass timing (incremental)
        let r2 = ing.run()
        print(String(format: "\nincremental re-run: %.3fs, %.1f KB read", r2.duration, Double(r2.bytesRead) / 1e3))
    }
}
