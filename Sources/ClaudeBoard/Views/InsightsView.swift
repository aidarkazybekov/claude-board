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
        let dark = scheme == .dark
        let cal = Calendar.current

        // 1. Requests per day by project (top 7 + Other)
        let topProjects = Dictionary(grouping: windowed, by: \.projectID)
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
        let seriesHex = ["#4E79A7", "#F28E2B", "#E15759", "#76B7B2", "#59A14F", "#EDC948", "#B07AA1"]
        var traces: [[String: Any]] = []
        for (rank, pid) in (topProjects + ["@rest"]).enumerated() {
            let subset = windowed.filter { pid == "@rest" ? !topProjects.contains($0.projectID) : $0.projectID == pid }
            if subset.isEmpty { continue }
            let counts = Dictionary(grouping: subset) { df.string(from: cal.startOfDay(for: $0.createdAt)) }.mapValues(\.count)
            let info = store.project(pid)
            traces.append([
                "type": "bar", "name": pid == "@rest" ? "Other" : info.name, "x": xs, "y": xs.map { counts[$0] ?? 0 },
                "marker": ["color": pid == "@rest" ? "#9AA0A6" : seriesHex[rank % seriesHex.count]],
                "hovertemplate": "%{x}<br>%{y} requests<extra>%{fullData.name}</extra>",
            ])
        }

        // 2. Ticket status per project
        let statusOrder: [TaskStatus] = [.needsYou, .inProgress, .todo, .backlog, .done]
        let statusHex: [TaskStatus: String] = [.needsYou: "#F58C1F", .inProgress: "#3880F5", .todo: "#73809A", .backlog: "#B8BCC4", .done: "#3DA85C"]
        let projByCount = Dictionary(grouping: windowed, by: \.projectID).sorted { $0.value.count > $1.value.count }.prefix(12)
        let projNames = projByCount.map { store.project($0.key).name }.reversed()
        var statusTraces: [[String: Any]] = []
        for s in statusOrder {
            let ys = projByCount.map { $0.value.filter { $0.status == s }.count }.reversed()
            statusTraces.append([
                "type": "bar", "orientation": "h", "name": s.title, "y": Array(projNames), "x": Array(ys),
                "marker": ["color": statusHex[s]!],
                "hovertemplate": "%{y}: %{x}<extra>\(s.title)</extra>",
            ])
        }

        // 3. When you work with Claude: weekday x hour heatmap
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for t in windowed {
            let wd = (cal.component(.weekday, from: t.createdAt) + 5) % 7  // Monday = 0
            grid[wd][cal.component(.hour, from: t.createdAt)] += 1
            for f in t.followUps where f.at >= since {
                let w2 = (cal.component(.weekday, from: f.at) + 5) % 7
                grid[w2][cal.component(.hour, from: f.at)] += 1
            }
        }
        let heat: [[String: Any]] = [[
            "type": "heatmap", "z": grid, "x": (0..<24).map { String(format: "%02d:00", $0) },
            "y": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
            "colorscale": [[0, dark ? "#1E1E22" : "#F4F5F7"], [1, "#5C66D9"]], "showscale": false,
            "hovertemplate": "%{y} %{x}<br>%{z} messages<extra></extra>", "xgap": 2, "ygap": 2,
        ]]

        // KPIs
        let done = windowed.filter { $0.status == .done }.count
        let tools = windowed.reduce(0) { $0 + $1.stats.toolCalls }
        let files = Set(windowed.flatMap(\.stats.filesTouched)).count
        let hours = windowed.reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) } / 3600

        func json(_ v: Any) -> String {
            (try? String(data: JSONSerialization.data(withJSONObject: v), encoding: .utf8)) ?? "[]"
        }
        let fg = dark ? "#E6E6E6" : "#1D1D1F"
        let grid2 = dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.07)"
        let muted = dark ? "#9A9AA0" : "#6E6E73"
        let cardBg = dark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.025)"

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
          :root { color-scheme: \(dark ? "dark" : "light"); }
          body { margin: 0; padding: 16px 18px; font: 13px -apple-system, system-ui; color: \(fg); background: transparent; }
          .kpis { display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-bottom: 14px; }
          .kpi { background: \(cardBg); border-radius: 10px; padding: 10px 12px; }
          .kpi b { display: block; font-size: 22px; font-weight: 600; font-variant-numeric: tabular-nums; }
          .kpi span { color: \(muted); font-size: 11px; }
          .card { background: \(cardBg); border-radius: 10px; padding: 8px 10px 2px; margin-bottom: 14px; }
          h3 { margin: 4px 4px 0; font-size: 13px; font-weight: 600; }
          p.sub { margin: 2px 4px 0; color: \(muted); font-size: 11px; }
          .row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
        </style>
        <script src="\(PlotlyAsset.scriptURL)"></script></head><body>
        <div class="kpis">
          <div class="kpi"><b>\(windowed.count)</b><span>requests to Claude</span></div>
          <div class="kpi"><b>\(done)</b><span>done</span></div>
          <div class="kpi"><b>\(String(format: hours < 10 ? "%.1f" : "%.0f", hours))h</b><span>Claude active time</span></div>
          <div class="kpi"><b>\(tools)</b><span>tool calls</span></div>
          <div class="kpi"><b>\(files)</b><span>files edited</span></div>
        </div>
        <div class="card"><h3>Requests per day</h3><p class="sub">\(store.scopeTitle) · \(store.period.title)</p><div id="daily" style="height:280px"></div></div>
        <div class="row">
          <div class="card"><h3>Tickets by status</h3><p class="sub">Top projects in this period</p><div id="status" style="height:\(max(220, projByCount.count * 26 + 80))px"></div></div>
          <div class="card"><h3>When you work with Claude</h3><p class="sub">Prompts and follow-ups by weekday and hour</p><div id="heat" style="height:260px"></div></div>
        </div>
        <script>
          const base = { paper_bgcolor: 'rgba(0,0,0,0)', plot_bgcolor: 'rgba(0,0,0,0)',
            font: { family: '-apple-system, system-ui', size: 11, color: '\(fg)' },
            margin: { l: 40, r: 10, t: 10, b: 36 }, hoverlabel: { font: { size: 12 } },
            xaxis: { gridcolor: '\(grid2)', zeroline: false }, yaxis: { gridcolor: '\(grid2)', zeroline: false },
            legend: { orientation: 'h', y: -0.18, font: { size: 11 } } };
          const cfg = { displayModeBar: false, responsive: true };
          // Plotly mutates layout objects (axis types), so each chart gets its own deep copy.
          const L = (extra) => Object.assign(JSON.parse(JSON.stringify(base)), extra);
          if (window.Plotly) {
            Plotly.newPlot('daily', \(json(traces)), L({ barmode: 'stack', bargap: 0.25 }), cfg);
            Plotly.newPlot('status', \(json(statusTraces)), L({ barmode: 'stack', margin: { l: 140, r: 10, t: 10, b: 36 }, yaxis: { automargin: true }, xaxis: { gridcolor: '\(grid2)', zeroline: false, tickformat: 'd', rangemode: 'tozero' } }), cfg);
            Plotly.newPlot('heat', \(json(heat)), L({ margin: { l: 40, r: 10, t: 10, b: 40 }, xaxis: { tickangle: 0, dtick: 3, showgrid: false }, yaxis: { autorange: 'reversed', showgrid: false } }), cfg);
          } else {
            document.body.insertAdjacentHTML('beforeend', '<p style="color:\(muted)">Plotly could not be loaded.</p>');
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
