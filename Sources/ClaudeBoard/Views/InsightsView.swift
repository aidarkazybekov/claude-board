import SwiftUI
import WebKit

/// Charts rendered with Plotly (bundled plotly-cartesian.min.js) inside a WKWebView.
struct InsightsView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PlotlyWebView(html: html())
            .id(scheme)
    }

    private func html() -> String {
        let tasks = store.scoped.filter { !$0.hidden }
        let since = store.period.since ?? (tasks.map(\.createdAt).min() ?? Date())
        let windowed = tasks.filter { $0.createdAt >= since }
        // Requests are what you asked an agent; planned tasks and suggestions are not requests.
        let requests = windowed.filter { $0.agentKind != nil && $0.origin != .suggested }
        let dark = scheme == .dark
        let cal = Calendar.current

        // 1. Requests per day by project (top 7 + Other), in each project's own color.
        let topProjects = Dictionary(grouping: requests, by: \.projectID)
            .sorted { $0.value.count > $1.value.count }.prefix(7).map(\.key)
        var dayList: [Date] = []
        var d = cal.startOfDay(for: since)
        let end = cal.startOfDay(for: Date())
        while d <= end && dayList.count < 400 {
            dayList.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let xs = dayList.map { df.string(from: $0) }
        var traces: [[String: Any]] = []
        for pid in topProjects + ["@rest"] {
            let subset = requests.filter { pid == "@rest" ? !topProjects.contains($0.projectID) : $0.projectID == pid }
            if subset.isEmpty { continue }
            let counts = Dictionary(grouping: subset) { df.string(from: cal.startOfDay(for: $0.createdAt)) }.mapValues(\.count)
            let info = store.project(pid)
            traces.append([
                "type": "bar", "name": pid == "@rest" ? "Other" : info.name, "x": xs, "y": xs.map { counts[$0] ?? 0 },
                "marker": ["color": pid == "@rest" ? "#9AA0B2" : Palette.projectHex[((info.colorIndex % 10) + 10) % 10]],
                "hovertemplate": "%{x}<br>%{y} requests<extra>%{fullData.name}</extra>",
            ])
        }
        let perDay = Dictionary(grouping: requests) { cal.startOfDay(for: $0.createdAt) }.mapValues(\.count)
        let busiest = perDay.max { $0.value < $1.value }

        // 2. What's still open: open work per project by status, with the done count written at the end.
        let openOrder: [TaskStatus] = [.backlog, .todo, .inProgress, .needsYou]
        let statusHex: [TaskStatus: String] = dark
            ? [.backlog: "#3A3E4A", .todo: "#6E7386", .inProgress: "#7FA2F2", .needsYou: "#FF6A3D"]
            : [.backlog: "#E2E4EC", .todo: "#B9BDCB", .inProgress: "#3D6FE0", .needsYou: "#FF6A3D"]
        let openByProject = Dictionary(grouping: tasks.filter { $0.status.isOpen }, by: \.projectID)
        let doneByProject = Dictionary(grouping: windowed.filter { $0.status == .done }, by: \.projectID).mapValues(\.count)
        let projOrder = openByProject.keys.sorted { (openByProject[$0]?.count ?? 0) > (openByProject[$1]?.count ?? 0) }.prefix(10)
        let projNames = projOrder.map { store.project($0).name }.reversed().map { $0 }
        var statusTraces: [[String: Any]] = []
        for s in openOrder {
            let ys = projOrder.map { p in openByProject[p]?.filter { $0.status == s }.count ?? 0 }.reversed().map { $0 }
            statusTraces.append([
                "type": "bar", "orientation": "h", "name": s.title, "y": projNames, "x": ys,
                "marker": ["color": statusHex[s]!],
                "hovertemplate": "%{y}: %{x}<extra>\(s.title)</extra>",
            ])
        }
        let doneNotes: [[String: Any]] = projOrder.map { p in
            ["x": openByProject[p]?.count ?? 0, "y": store.project(p).name, "text": "  \(doneByProject[p] ?? 0) done",
             "showarrow": false, "xanchor": "left", "font": ["size": 12, "color": dark ? "#9499AB" : "#5F6475"]]
        }

        // 3. Who did the work: requests and active hours per agent.
        let byAgent = Dictionary(grouping: requests) { $0.agentKind ?? .claudeCode }
        let agents = Agent.allCases.filter { byAgent[$0] != nil }.reversed().map { $0 }
        let agentTrace: [[String: Any]] = [[
            "type": "bar", "orientation": "h", "y": agents.map(\.title), "x": agents.map { byAgent[$0]?.count ?? 0 },
            "marker": ["color": dark ? "#EEEFF4" : "#14161F"],
            "text": agents.map { a -> String in
                let h = (byAgent[a] ?? []).reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) } / 3600
                return String(format: h < 10 ? "%d · %.1f h" : "%d · %.0f h", byAgent[a]?.count ?? 0, h)
            },
            "textposition": "outside", "cliponaxis": false,
            "textfont": ["color": dark ? "#9499AB" : "#5F6475", "size": 12],
            "hovertemplate": "%{y}: %{x} requests<extra></extra>",
        ]]

        // 4. When you work with agents: weekday x hour heatmap
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for t in requests {
            let wd = (cal.component(.weekday, from: t.createdAt) + 5) % 7  // Monday = 0
            grid[wd][cal.component(.hour, from: t.createdAt)] += 1
            for f in t.followUps where f.at >= since {
                let w2 = (cal.component(.weekday, from: f.at) + 5) % 7
                grid[w2][cal.component(.hour, from: f.at)] += 1
            }
        }
        let heat: [[String: Any]] = [[
            "type": "heatmap", "z": grid, "x": (0..<24).map { String(format: "%02d", $0) },
            "y": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            "colorscale": dark ? [[0, "#22252E"], [0.35, "#2B3D66"], [0.7, "#4D78D6"], [1, "#9FB9F5"]]
                               : [[0, "#F5F6FA"], [0.35, "#D8E3FB"], [0.7, "#8FB0F5"], [1, "#3D6FE0"]],
            "showscale": false,
            "hovertemplate": "%{y} %{x}:00<br>%{z} messages<extra></extra>", "xgap": 3, "ygap": 3,
        ]]

        // KPIs
        let done = requests.filter { $0.status == .done }.count
        let tools = requests.reduce(0) { $0 + $1.stats.toolCalls }
        let files = Set(requests.flatMap(\.stats.filesTouched)).count
        let hours = requests.reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) } / 3600
        let pct = requests.isEmpty ? 0 : Int((Double(done) / Double(requests.count) * 100).rounded())
        let busyText: String = {
            guard let busiest, busiest.value > 1 else { return "" }
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return " Busiest day: \(f.string(from: busiest.key)), with \(busiest.value)."
        }()
        let agentCount = Set(requests.compactMap(\.agentKind)).count

        func json(_ v: Any) -> String {
            (try? String(data: JSONSerialization.data(withJSONObject: v), encoding: .utf8)) ?? "[]"
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let ink = dark ? "#EEEFF4" : "#14161F"
        let ink2 = dark ? "#C3C7D3" : "#3E4252"
        let muted = dark ? "#9499AB" : "#5F6475"
        let surface = dark ? "#1B1D24" : "#FFFFFF"
        let gridC = dark ? "rgba(255,255,255,0.07)" : "#EEF0F5"
        let heroBg = dark ? "#EEEFF4" : "#14161F"
        let heroFg = dark ? "#14161F" : "#FFFFFF"
        let heroSub = dark ? "#3E4252" : "#C9CCD8"
        let tints = dark ? ["#1C2840", "#2A2340", "#15302A"] : ["#EAF1FE", "#F1EDFD", "#E7F8F3"]
        let scope = esc(store.scopeTitle)
        let periodText = store.period == .all ? "all time" : store.period == .day ? "today" : "the last \(store.period.title)"

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: \(dark ? "dark" : "light"); }
          * { box-sizing: border-box; }
          body { margin: 0; padding: 2px 26px 32px; font: 13px -apple-system, system-ui; color: \(ink); background: transparent; -webkit-font-smoothing: antialiased; }
          .num { font-family: ui-rounded, -apple-system, system-ui; font-weight: 800; letter-spacing: -0.04em; line-height: 1; font-variant-numeric: tabular-nums; }
          .kpis { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr; gap: 14px; margin-bottom: 18px; }
          .tile { border-radius: 22px; padding: 18px 20px; display: flex; flex-direction: column; justify-content: space-between; gap: 8px; min-height: 142px; }
          .tile .label { font-size: 13.5px; font-weight: 700; }
          .tile .note { font-size: 12.5px; font-weight: 600; }
          .hero { background: \(heroBg); color: \(heroFg); }
          .hero .label, .hero .note { color: \(heroSub); }
          .hero .num { font-size: 68px; }
          .small .num { font-size: 40px; }
          .small .label, .small .note { color: \(ink2); }
          .card { background: \(surface); border-radius: 22px; padding: 18px 20px 8px; margin-bottom: 18px; }
          h2 { margin: 0; font: 800 17px ui-rounded, -apple-system, system-ui; letter-spacing: -0.01em; }
          p.sub { margin: 3px 0 0; color: \(muted); font-size: 12px; font-weight: 600; }
          .row { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
          .empty { color: \(muted); font-weight: 600; padding: 30px 4px; }
          @media (max-width: 900px) { .kpis { grid-template-columns: 1fr 1fr; } .row { grid-template-columns: 1fr; } }
        </style>
        <script src="\(PlotlyAsset.scriptURL)"></script></head><body>
        <div class="kpis">
          <div class="tile hero"><span class="label">Requests to your agents</span><span class="num">\(requests.count)</span>
            <span class="note">\(requests.isEmpty ? "None in \(periodText)." : "\(done) done, that's \(pct)%.\(busyText)")</span></div>
          <div class="tile small" style="background: \(tints[0])"><span class="label">Agent time</span><span class="num">\(String(format: hours < 10 ? "%.1f" : "%.0f", hours)) h</span><span class="note">active; gaps over 5 min left out</span></div>
          <div class="tile small" style="background: \(tints[1])"><span class="label">Tool calls</span><span class="num">\(tools.formatted())</span><span class="note">\(requests.isEmpty ? "" : "about \(tools / max(1, requests.count)) per request")</span></div>
          <div class="tile small" style="background: \(tints[2])"><span class="label">Files edited</span><span class="num">\(files.formatted())</span><span class="note">unique files\(agentCount > 1 ? ", \(agentCount) agents" : "")</span></div>
        </div>
        <div class="card"><h2>Every day, by project</h2><p class="sub">\(scope) · requests in \(periodText)</p><div id="daily" style="height:300px"></div></div>
        <div class="row">
          <div class="card"><h2>What's still open</h2><p class="sub">By status, with what got done in \(periodText)</p><div id="status" style="height:\(max(240, projOrder.count * 34 + 90))px"></div></div>
          <div class="card"><h2>Who did the work</h2><p class="sub">Requests per agent, with active hours</p><div id="agents" style="height:\(max(200, agents.count * 46 + 60))px"></div></div>
        </div>
        <div class="card"><h2>When you work with agents</h2><p class="sub">Prompts and follow-ups by weekday and hour</p><div id="heat" style="height:270px"></div></div>
        <script>
          const base = { paper_bgcolor: 'rgba(0,0,0,0)', plot_bgcolor: 'rgba(0,0,0,0)',
            font: { family: '-apple-system, system-ui', size: 12, color: '\(muted)' },
            margin: { l: 44, r: 12, t: 30, b: 34 }, hoverlabel: { font: { size: 12 } },
            xaxis: { gridcolor: '\(gridC)', zeroline: false, linecolor: '\(gridC)' }, yaxis: { gridcolor: '\(gridC)', zeroline: false },
            legend: { orientation: 'h', x: 0, y: 1.08, xanchor: 'left', yanchor: 'bottom', font: { size: 12, color: '\(ink)' } }, bargap: 0.28 };
          const cfg = { displayModeBar: false, responsive: true };
          // Plotly mutates layout objects (axis types), so each chart gets its own deep copy.
          const L = (extra) => Object.assign(JSON.parse(JSON.stringify(base)), extra);
          const empty = (id) => document.getElementById(id).insertAdjacentHTML('beforeend', '<p class="empty">Nothing in this period yet.</p>');
          if (window.Plotly) {
            const daily = \(json(traces));
            if (daily.length) Plotly.newPlot('daily', daily, L({ barmode: 'stack', legend: Object.assign({}, base.legend, { traceorder: 'normal' }), yaxis: { gridcolor: '\(gridC)', zeroline: false, rangemode: 'tozero', tickformat: 'd', dtick: \(perDay.values.max() ?? 0 <= 6 ? 1 : 0) || undefined } }), cfg); else empty('daily');
            const st = \(json(statusTraces));
            if (\(projOrder.count) > 0) Plotly.newPlot('status', st, L({ barmode: 'stack', annotations: \(json(doneNotes)), margin: { l: 10, r: 70, t: 30, b: 30 },
              yaxis: { automargin: true, tickfont: { size: 13, color: '\(ink)' }, ticksuffix: '  ' }, xaxis: { gridcolor: '\(gridC)', zeroline: false, tickformat: 'd', rangemode: 'tozero' } }), cfg); else empty('status');
            const ag = \(json(agentTrace));
            if (\(agents.count) > 0) Plotly.newPlot('agents', ag, L({ showlegend: false, bargap: \(agents.count < 3 ? 0.6 : 0.35), margin: { l: 10, r: 90, t: 10, b: 20 },
              yaxis: { automargin: true, tickfont: { size: 13, color: '\(ink)' }, ticksuffix: '  ' }, xaxis: { visible: false } }), cfg); else empty('agents');
            Plotly.newPlot('heat', \(json(heat)), L({ margin: { l: 44, r: 10, t: 10, b: 30 }, xaxis: { tickangle: 0, dtick: 3, showgrid: false, linecolor: 'rgba(0,0,0,0)' }, yaxis: { autorange: 'reversed', showgrid: false } }), cfg);
          } else {
            document.body.insertAdjacentHTML('beforeend', '<p class="empty">Plotly could not be loaded.</p>');
          }
        </script></body></html>
        """
    }
}

enum PlotlyAsset {
    static let fileName = "plotly-cartesian.min.js"

    /// Copies the bundled Plotly build next to the generated page so the web view can read both.
    /// Returns the relative script path, or a pinned CDN build if no local copy exists.
    static func prepare() -> String {
        let dest = Paths.appSupport.appendingPathComponent(fileName)
        // Inside the app bundle, or Resources/ next to the package when run with `swift run`.
        let source: URL? = Bundle.main.url(forResource: "plotly-cartesian.min", withExtension: "js") ?? {
            let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/" + fileName)
            return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
        }()
        if let source {
            let srcSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue
            let dstSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue
            if srcSize != dstSize {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: source, to: dest)
            }
        }
        if FileManager.default.fileExists(atPath: dest.path) { return fileName }
        return "https://cdnjs.cloudflare.com/ajax/libs/plotly.js/3.0.1/plotly.min.js"
    }

    static let scriptURL = prepare()
}

struct PlotlyWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        guard context.coordinator.last != html else { return }
        context.coordinator.last = html
        let dir = Paths.appSupport
        let page = dir.appendingPathComponent("insights.html")
        try? html.write(to: page, atomically: true, encoding: .utf8)
        web.loadFileURL(page, allowingReadAccessTo: dir)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var last = "" }
}
