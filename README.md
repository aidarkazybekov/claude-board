<div align="center">

<img src="docs/site/icon-180.png" width="88" height="88" alt="">

# Pitwall

### Everything you ask your coding agents, on one board.

A native Mac app that turns what you ask Claude Code, Codex, Cursor, Gemini CLI and Antigravity into
tickets, next to the tasks you plan for each project. See what each agent is working on, what it
finished, and which ones are waiting on you, then hand the next task to whichever agent you like.

<sub>Pitwall was called ClaudeBoard until 0.4. Installing it over ClaudeBoard keeps your tasks and settings.</sub>

[![CI](https://github.com/aidarkazybekov/pitwall/actions/workflows/ci.yml/badge.svg)](https://github.com/aidarkazybekov/pitwall/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/aidarkazybekov/pitwall)](https://github.com/aidarkazybekov/pitwall/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black)

**[Download for Mac](https://github.com/aidarkazybekov/pitwall/releases/latest/download/Pitwall-macOS-arm64.zip)** &nbsp;·&nbsp; **[Website](https://aidarkazybekov.github.io/pitwall/)** &nbsp;·&nbsp; **[See your own numbers](https://aidarkazybekov.github.io/pitwall/#yours)** &nbsp;·&nbsp; **[Guide](docs/GUIDE.md)**

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/site/hero-dark.jpg">
  <img src="docs/site/hero-light.jpg" width="920" alt="Pitwall: requests to Claude Code, Codex, Cursor, Gemini CLI and Antigravity next to your own planned tasks, in Backlog, To do, In progress, Needs you and Done">
</picture>

<sub>Free and open source · Reads your agents' local history, never changes it · No account, no server, no analytics</sub>

</div>

## Install in one line

```bash
curl -fsSL https://aidarkazybekov.github.io/pitwall/install.sh | bash
```

It downloads the latest release, checks its SHA-256, installs `Pitwall.app` into `/Applications`
(or `~/Applications`) and opens it, with no security prompt to click through. Run it again to update.
[Read the script](docs/install.sh) first if you like; it's about 70 lines.

**Needs** macOS 15 Sequoia or later and at least one coding agent on the same Mac: Claude Code
(the CLI or the desktop app's Code tab), Codex (the CLI or the desktop app), Cursor, Gemini CLI or
Antigravity. On first launch, pick the folders that hold your code; every git repo inside becomes a
project.

<details>
<summary><b>Other ways to install:</b> download the zip, or build from source</summary>

#### Download the zip

1. [Download the latest build](https://github.com/aidarkazybekov/pitwall/releases/latest/download/Pitwall-macOS-arm64.zip)
   (or pick a version from [Releases](../../releases)). It's built for Apple Silicon; on Intel
   Macs, build from source.
2. Unzip it and move `Pitwall.app` to Applications.
3. The app isn't notarized yet, so macOS 15 blocks the first launch. Open it once, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**. The old right-click → Open
   shortcut no longer works on macOS 15. Alternatively, run
   `xattr -dr com.apple.quarantine /Applications/Pitwall.app`.

#### Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), Swift 6.

```bash
git clone https://github.com/aidarkazybekov/pitwall.git
cd pitwall
scripts/build-app.sh          # builds, bundles, installs to ~/Applications
```

On first launch, pick the folders that hold your projects (it suggests `~/Developer`,
`~/Projects`, `~/code` and similar if they exist). Every git repo inside becomes a project.

</details>

## What it does

<table>
<tr>
<td valign="middle">

### Know which agent is waiting on you

**Needs you** gathers every session that stopped on a question or a permission prompt, whichever
agent ran it, with the question itself, the outcome so far and a **Resume** button. The menu bar
shows the count even with the window closed.

</td>
<td><img src="docs/site/needs-you.jpg" width="560" alt="Needs you: a Codex session waiting on an answer, with its question and a Resume button"></td>
</tr>
<tr>
<td><img src="docs/site/plan.jpg" width="560" alt="Plan view: each project with its open tasks and an add-a-task line"></td>
<td valign="middle">

### Plan each project's tasks

Write down what every app still needs before any agent knows about it. Keep the list in Pitwall
or as markdown files in the repo, where teammates and agents read the same backlog. **Start with**
hands a task to the agent you pick, and mentioning a key like `T-015` in any prompt links that
session to the task.

</td>
</tr>
<tr>
<td valign="middle">

### A worklog that writes itself

Day by day: what you asked, what each agent did, how long it worked and which files it touched.
Handy for stand-ups and timesheets. **Insights** charts when and where you work, and which agent
did the work.

</td>
<td><img src="docs/site/worklog.jpg" width="560" alt="Worklog: requests and outcomes grouped by day, with active time"></td>
</tr>
</table>

## Try it before you install

- **In your browser:** [drag cards on a live copy of the board](https://aidarkazybekov.github.io/pitwall/#try), or
  [point the site at your `~/.claude/projects` folder](https://aidarkazybekov.github.io/pitwall/#yours) to see what Pitwall
  would find. It's read in the tab; nothing is uploaded.
- **In the app:** **Help → Try the Demo Board** opens a fictional company with work from all five
  agents in every state and a shared backlog. Nothing touches your real data.

<p align="center"><img src="docs/media/tour.gif" width="820" alt="A short tour: Board, a ticket waiting on you, Plan, an agent at work, Worklog and Insights"></p>

The **[guide](docs/GUIDE.md)** walks through every feature with screenshots. It's also in the app
under **Help → Pitwall Guide** (⌘/).

## Features

- **Plan view:** each project with its own open tasks and an "Add a task for …" line. Quick-add
  understands `!high`, `!urgent`, `!low` (or `!p0`–`!p3`).
- **Board:** Backlog, To Do, In Progress, Needs You and Done. Drag to move, or quick-add at the
  top of a column.
- **List:** sortable table of every ticket.
- **Worklog:** day by day, what you asked and what each agent did, with active time.
- **Insights:** requests per day, status per project, which agent did the work, when you work
  (Plotly, bundled, offline).
- **Live status:** which sessions are running, which are busy, and what is waiting on you, also
  in the menu bar, with a notification when an agent stops to ask.
- **Agents:** filter the board to one agent, or turn agents you don't use off in Settings.
- **Start with:** hands a task to Claude Code, Codex or Gemini CLI in Terminal, or opens the
  project in Cursor or Antigravity with the task on your clipboard.
- **Resume:** reopens a ticket's session where the agent stopped.

## Privacy

Everything stays on your Mac. Pitwall reads each agent's local history read-only. It writes
only to its own data folder (`~/Library/Application Support/Pitwall/`) and, when you edit
them, to your backlog markdown files. It makes no network requests.

## Reference

<details>
<summary><b>Where your tasks live</b>: this Mac, or a backlog folder in the repo</summary>

| Storage | When | Who sees it |
|---|---|---|
| **Backlog folder** (markdown files in the repo) | The project, or a folder above it, has a `backlog/` folder | You, teammates via git, and your agents ("read backlog/tasks/T-007-….md") |
| **This Mac** | No backlog folder | Only you, in Pitwall |

"Keep Tasks in the Repo" (project menu) creates `<project>/backlog/` with a README and an index,
and moves that project's local tasks into it.

</details>

<details>
<summary><b>Backlog folder format</b>: one markdown file per task</summary>

One markdown file per task with front matter, optionally indexed by a `BACKLOG.md` table:

```markdown
---
id: T-015
title: Web deploy script skips the pricing page
area: Frontend
project: apps/web         # optional; otherwise inferred from the title
priority: P1              # P0–P3, or urgent/high/medium/low
status: backlog           # backlog · todo · in-progress · blocked · done
captured: 2026-08-27
---

# T-015 — Web deploy script skips the pricing page

Description in plain words.

- [ ] checklist items become sub-steps
```

- **Discovery:** folders named `backlog/`, `.backlog/` or `tasks/` under your roots are found
  automatically. The [Backlog.md](https://github.com/MrLesk/Backlog.md) layout
  (`backlog/tasks/task-1 - Title.md`, `status: To Do`) works too.
- **Which project a task belongs to:** an explicit `project:` field wins. Otherwise it's the
  first project named in `owner-session`, the title or the area ("Web deploy script…" →
  `apps/web`). Otherwise the folder's own project. Project Settings has aliases (e.g. "fe" for
  `frontend`).
- **Edits are surgical:** changing status, priority, title, labels, due date or a checkbox
  rewrites only that front-matter line, checkbox or `BACKLOG.md` cell. The rest of the file is
  left byte-for-byte. A status keeps its original word while it stays in the same column. New
  tasks get the next id and an index row.

</details>

<details>
<summary><b>How your agents' work is read</b>: which local files, and how requests become tickets</summary>

| Agent | Source | What it gives |
|---|---|---|
| Claude Code | `~/.claude/projects/*/<session>.jsonl` | Prompts, plan steps, wrap-up recaps, pending questions, files edited, active time |
| | `~/.claude/history.jsonl` | Prompts from sessions whose transcripts were already cleaned up |
| | `~/Library/Application Support/Claude/claude-code-sessions` | Desktop app session titles and "needs your action" |
| | `~/.claude/sessions/<pid>.json` | Which sessions are running, and whether Claude is busy |
| Codex | `~/.codex/state_N.sqlite`, `thread_history_N.sqlite`, or `sessions/**/rollout-*.jsonl` | Requests, replies, commands, file changes, questions and approval prompts |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Agent chats, their folder, tool calls, to-dos, commands waiting for approval |
| Gemini CLI | `~/.gemini/tmp/<project>/chats/` | Sessions with their requests, replies and tool calls |
| Antigravity | `~/.gemini/antigravity/brain/<conversation>/` | One ticket per conversation: its plan, the task checklist as steps, the walkthrough as the outcome |

Databases are copied before reading, so Pitwall never locks or writes next to another app's files.

- Each real request becomes a ticket keyed per project (`WEB-42`).
- Short replies ("yes", "1", "go ahead") fold into the ticket they answer.
- Columns follow the session: Needs you when the agent ended on a question or is waiting for
  permission, In progress while it works or has open plan steps, and so on. Drag a card to override.
- While running, it refreshes every 20 s and reads only the new bytes. A first full scan of a few
  hundred MB of transcripts takes a few seconds.

</details>

<details>
<summary><b>Development</b>: build, self-test, dump, snapshots, code layout</summary>

```bash
swift build
PITWALL_DATA_DIR=$(mktemp -d) .build/debug/Pitwall --selftest     # parser, merge and backlog-file checks
.build/debug/Pitwall --dump 30                                        # what ingestion sees on your machine
.build/debug/Pitwall --snapshot /tmp/cb-shots                         # render every screen to PNG
.build/debug/Pitwall --demo                                           # run on sample data (add --dump to inspect it)
```

README and site screenshots, the GIF and the tour videos are generated from the demo board,
off screen (the app never shows a window or takes focus):

```bash
scripts/build-app.sh --no-install
build/Pitwall.app/Contents/MacOS/Pitwall --media "$PWD/build/raw"
swift scripts/make-media.swift build/raw docs build/media
```

```
Sources/Pitwall/
  Ingest/   TranscriptParser, Sources (history/desktop/live), TaskFolder (backlog files),
            Ingestor (orchestration, status inference), PromptText (request heuristics),
            CodexReader, CursorReader, GeminiReader, AntigravityReader, TicketBuilder
  Model/    Models, Store (merge, links, edits, persistence), Paths (roots, discovery), Launcher
  Views/    Plan, Board, List, Worklog, Insights, TaskDetail, NewTask, Settings, MenuBar
scripts/    build-app.sh, make-icon.swift, make-media.swift (screenshots, GIF, videos)
docs/       GUIDE.md, media/, the site (index.html, ru/, site/)
Resources/  plotly-cartesian.min.js
```

None of these formats is a public API, and any of them can change between versions. If tickets
look wrong after an update, `--dump` shows what the readers see. Issues and PRs welcome.

</details>

## Contributing

Ideas, bug reports and pull requests are welcome.

- **Ideas and bugs:** [open an issue](../../issues/new/choose). The templates ask for what's needed.
- **Code:** see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, ground rules (local only, never
  write to `~/.claude`, surgical backlog edits) and the self-test.
- **New here?** Start with a
  [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).

If Pitwall saves you time, a star helps other people who work with coding agents find it.

## License

MIT. See [LICENSE](LICENSE). Bundles [plotly.js](https://github.com/plotly/plotly.js) (MIT,
© Plotly, Inc.) in `Resources/`.

<sub>Community project. Not affiliated with or endorsed by Anthropic, OpenAI, Anysphere or Google. Claude, Codex, Cursor, Gemini and Antigravity are trademarks of their owners.</sub>
