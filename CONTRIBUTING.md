# Contributing to Pitwall

Thanks for helping. Ideas, bug reports, docs fixes and code are all welcome. Small PRs are great.

## Ways to help

- **Report a bug.** Open an issue with the *Bug report* template. Include your macOS, the agent
  and its version (`claude --version`, `codex --version`, …): agents change their history formats
  between versions, and that is the most common cause of wrong tickets.
- **Suggest an idea.** Open an issue with the *Feature request* template. Describe the problem
  first, then your proposal.
- **Pick up a task.** Issues labelled
  [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  are self-contained and say which files to touch. Comment on the issue so nobody duplicates
  work.
- **Improve the docs.** If something confused you, a README fix is a fine first PR.

## Development setup

You need macOS 15+ and the Xcode Command Line Tools (`xcode-select --install`), Swift 6. Full
Xcode is optional.

```bash
git clone https://github.com/aidarkazybekov/pitwall.git
cd pitwall
swift build                                   # debug build
scripts/build-app.sh --no-install && open build/Pitwall.app
```

Useful modes on the binary:

```bash
# Unit-style checks (parser, merge, backlog files). Uses a throwaway data folder.
PITWALL_DATA_DIR=$(mktemp -d) .build/debug/Pitwall --selftest

# What ingestion sees on your machine (prints your prompt titles, so don't paste it unredacted).
.build/debug/Pitwall --dump 30

# Log every refresh (counts, timing) while the app runs, e.g. when tasks don't show up.
PITWALL_LOG=/tmp/pitwall.log .build/debug/Pitwall

# Notifications need the app bundle. Log them instead of showing them (no permission prompt):
PITWALL_LOG=/tmp/pitwall.log PITWALL_NOTIFY_DRYRUN=1 build/Pitwall.app/Contents/MacOS/Pitwall

# Render every screen to PNGs, handy for UI PRs.
.build/debug/Pitwall --snapshot /tmp/cb-shots

# Render every screen of the demo board to PNGs, light and dark, without showing a window or a Dock
# icon (safe to run while you work). Good for checking a UI change.
.build/debug/Pitwall --render /tmp/cb-render

# Run on the sample "Acme" demo board (never reads your real data).
.build/debug/Pitwall --demo

# README and site media, also off screen: run from the app bundle so the share card gets the icon.
build/Pitwall.app/Contents/MacOS/Pitwall --media "$PWD/build/raw"
swift scripts/make-media.swift build/raw docs build/media
```

The code layout is in the [README](README.md#development).

## Ground rules

These keep the app trustworthy. Please don't break them in a PR:

1. **Local only.** No network requests, telemetry or accounts. Everything runs from the user's own
   files.
2. **Agents' files are read-only.** Never write to `~/.claude`, `~/.codex`, `~/.gemini`, Cursor's
   or Antigravity's support folders, or the Claude app's. Databases are read from a copy in
   Pitwall's own cache (`SQLiteSnapshot`).
3. **Backlog edits are surgical.** When the app changes a task file or `BACKLOG.md`, it rewrites
   only the line or cell that changed. People keep these files in git; noisy diffs or reformatting
   are bugs.
4. **Persisted data stays readable.** New fields on `Codable` structs saved to disk (`TaskItem`,
   `IngestedStore`, `UserStore`, …) must be optional, so existing users' data still decodes.
5. **Charts use the bundled Plotly** (`Resources/plotly-cartesian.min.js`, rendered in a
   `WKWebView`). Please don't add another chart library.
6. **No new dependencies** without discussing it in an issue first. The project builds with
   nothing but the Swift toolchain.

## Pull requests

- Branch from `main`. One topic per PR.
- Run `--selftest` and make sure it passes. If you change parsing, merge or backlog-file logic,
  add a check to `Sources/Pitwall/SelfTest.swift`.
- For UI changes, attach a screenshot. `--render` and `--snapshot` work without Screen Recording permission.
- The look lives in `Views/Studio.swift` (colors with dark-mode twins, type, buttons, pills) and
  `Palette` in `Views/Components.swift`. Use those tokens instead of system colors.
- Agent readers live in `Ingest/`: `TranscriptParser` (Claude Code), `CodexReader` (Codex, its
  SQLite databases first, JSONL rollouts as a fallback), `CursorReader` (Cursor's `state.vscdb`),
  `GeminiReader` (Gemini CLI chats) and `AntigravityReader` (Antigravity's brain folders). The last
  three build tickets with `TicketBuilder`, so follow-ups, tool counts and active time work the same
  for every agent. Each agent's data folder can be pointed elsewhere for tests: `PITWALL_CLAUDE_DIR`, `PITWALL_CODEX_DIR`, `PITWALL_CURSOR_DIR`,
  `PITWALL_GEMINI_DIR`, `PITWALL_ANTIGRAVITY_DIR`.
  **Use the demo board (`--demo`), not your real board**: real boards show your prompts and
  project names.
- CI builds the app and runs the self-test on every PR.

## Releases (maintainers)

Attach three files:

- `Pitwall-<version>-macOS-arm64.zip`
- `Pitwall-macOS-arm64.zip`: the same zip under a stable name. The website's and README's
  one-click "Download for Mac" and `docs/install.sh` use
  `releases/latest/download/Pitwall-macOS-arm64.zip`.
- `Pitwall-macOS-arm64.zip.sha256`: `shasum -a 256 Pitwall-macOS-arm64.zip > Pitwall-macOS-arm64.zip.sha256`.
  The installer refuses a zip that doesn't match it.

## Privacy when reporting

Transcripts, `--dump` output and screenshots can contain your prompts, file paths, client names and
secrets. Redact them before posting. A minimal synthetic reproduction is the most useful kind,
e.g. a few fake JSONL lines that show the problem.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
