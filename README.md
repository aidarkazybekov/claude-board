# ClaudeBoard

A native macOS task board for your projects and for everything you ask
[Claude Code](https://docs.anthropic.com/en/docs/claude-code). Think Jira/Asana, but it fills
itself in from your Claude sessions.

It shows two kinds of tickets on one board:

- **Your tasks**: what each project still needs, planned before Claude knows about it.
- **Claude's work**: every request you gave Claude Code, read from its local logs, with its plan,
  outcome, the files it edited, and whether it is waiting on you.

Mention a task's key in any Claude prompt ("look at T-015", "[WEB-3] …") and that session is
linked to the task, so the task shows Claude's live activity.

> Community project. Not affiliated with or endorsed by Anthropic. "Claude" is a trademark of
> Anthropic.

## Install

**Requirements:** macOS 14 Sonoma or later. Claude Code (CLI or the desktop app's Code tab) used on
the same Mac.

### Download

1. Get `ClaudeBoard-<version>-macOS-arm64.zip` from
   [Releases](../../releases/latest). The build is for Apple Silicon; Intel Macs should build from
   source.
2. Unzip it and move `ClaudeBoard.app` to `/Applications` or `~/Applications`.
3. The app is not notarized. The first time, right-click it and choose **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ClaudeBoard.app
   ```

### Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), Swift 6.

```bash
git clone https://github.com/aidarkazybekov/claude-board.git
cd claude-board
scripts/build-app.sh          # builds, bundles, installs to ~/Applications
```

On first launch, pick the folders that hold your projects (it suggests `~/Developer`,
`~/Projects`, `~/code` and similar if they exist). Every git repo inside becomes a project.

## Features

- **Plan view:** each project with its own open tasks and an "Add a task for …" line. Quick-add
  understands `!high`, `!urgent`, `!low` (or `!p0`–`!p3`).
- **Board:** Backlog, To Do, In Progress, Needs You and Done. Drag to move, or quick-add at the
  top of a column.
- **List:** sortable table of every ticket.
- **Worklog:** day by day, what you asked and what Claude did, with active time.
- **Insights:** requests per day, status per project, when you work (Plotly, bundled, offline).
- **Live status:** which sessions are running, which are busy, and what is waiting on you, also
  in the menu bar.
- **Start with Claude:** opens Terminal in the project folder and hands the task to Claude Code.
- **Resume:** reopens a ticket's session with `claude --resume`.

## Where your tasks live

| Storage | When | Who sees it |
|---|---|---|
| **Backlog folder** (markdown files in the repo) | The project, or a folder above it, has a `backlog/` folder | You, teammates via git, and Claude ("read backlog/tasks/T-007-….md") |
| **This Mac** | No backlog folder | Only you, in ClaudeBoard |

"Keep Tasks in the Repo" (project menu) creates `<project>/backlog/` with a README and an index,
and moves that project's local tasks into it.

### Backlog folder format

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

## How Claude's work is read

| Source | What it gives |
|---|---|
| `~/.claude/projects/*/<session>.jsonl` | Prompts, plan steps, wrap-up recaps, pending questions, files edited, active time |
| `~/.claude/history.jsonl` | Prompts from sessions whose transcripts were already cleaned up |
| `~/Library/Application Support/Claude/claude-code-sessions` | Desktop app session titles and "needs your action" |
| `~/.claude/sessions/<pid>.json` | Which sessions are running, and whether Claude is busy |

- Each real request becomes a ticket keyed per project (`WEB-42`).
- Short replies ("yes", "1", "go ahead") fold into the ticket they answer.
- Columns follow the transcript: Needs You when Claude ended on a question, In Progress while it
  works or has open plan steps, and so on. Drag a card to override.
- While running, it refreshes every 20 s and reads only the new bytes. A first full scan of a few
  hundred MB of transcripts takes a few seconds.

## Privacy

Everything stays on your Mac. ClaudeBoard reads Claude Code's local files read-only. It writes
only to its own data folder (`~/Library/Application Support/ClaudeBoard/`) and, when you edit
them, to your backlog markdown files. It makes no network requests.

## Development

```bash
swift build
CLAUDEBOARD_DATA_DIR=$(mktemp -d) .build/debug/ClaudeBoard --selftest     # parser, merge and backlog-file checks
.build/debug/ClaudeBoard --dump 30                                        # what ingestion sees on your machine
.build/debug/ClaudeBoard --snapshot /tmp/cb-shots                         # render every screen to PNG
```

```
Sources/ClaudeBoard/
  Ingest/   TranscriptParser, Sources (history/desktop/live), TaskFolder (backlog files),
            Ingestor (orchestration, status inference), PromptText (request heuristics)
  Model/    Models, Store (merge, links, edits, persistence), Paths (roots, discovery), Launcher
  Views/    Plan, Board, List, Worklog, Insights, TaskDetail, NewTask, Settings, MenuBar
scripts/    build-app.sh, make-icon.swift
Resources/  plotly-cartesian.min.js
```

Claude Code's log format is not a public API and can change between versions. If tickets look
wrong after an update, `--dump` shows what the parser sees. Issues and PRs welcome.

## Contributing

Ideas, bug reports and pull requests are welcome.

- **Ideas and bugs:** [open an issue](../../issues/new/choose). The templates ask for what's needed.
- **Code:** see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, ground rules (local only, never
  write to `~/.claude`, surgical backlog edits) and the self-test.
- **New here?** Start with a
  [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).

## License

MIT. See [LICENSE](LICENSE). Bundles [plotly.js](https://github.com/plotly/plotly.js) (MIT,
© Plotly, Inc.) in `Resources/`.
