# Contributing to ClaudeBoard

Thanks for helping. Ideas, bug reports, docs fixes and code are all welcome. Small PRs are great.

## Ways to help

- **Report a bug.** Open an issue with the *Bug report* template. Include your macOS and
  `claude --version`: Claude Code's log format changes between versions, and that is the most
  common cause of wrong tickets.
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
git clone https://github.com/aidarkazybekov/claude-board.git
cd claude-board
swift build                                   # debug build
scripts/build-app.sh --no-install && open build/ClaudeBoard.app
```

Useful modes on the binary:

```bash
# Unit-style checks (parser, merge, backlog files). Uses a throwaway data folder.
CLAUDEBOARD_DATA_DIR=$(mktemp -d) .build/debug/ClaudeBoard --selftest

# What ingestion sees on your machine (prints your prompt titles, so don't paste it unredacted).
.build/debug/ClaudeBoard --dump 30

# Render every screen to PNGs, handy for UI PRs.
.build/debug/ClaudeBoard --snapshot /tmp/cb-shots

# Run on the sample "Acme" demo board (never reads your real data). Add --snapshot <dir> for
# the curated README scenes, then `swift scripts/make-media.swift <dir> docs/media build/media`.
.build/debug/ClaudeBoard --demo
```

The code layout is in the [README](README.md#development).

## Ground rules

These keep the app trustworthy. Please don't break them in a PR:

1. **Local only.** No network requests, telemetry or accounts. Everything runs from the user's own
   files.
2. **Claude Code's files are read-only.** Never write to `~/.claude` or the Claude app's support
   folder.
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
  add a check to `Sources/ClaudeBoard/SelfTest.swift`.
- For UI changes, attach a screenshot. `--snapshot` works without Screen Recording permission.
  **Use the demo board (`--demo`), not your real board**: real boards show your prompts and
  project names.
- CI builds the app and runs the self-test on every PR.

## Privacy when reporting

Transcripts, `--dump` output and screenshots can contain your prompts, file paths, client names and
secrets. Redact them before posting. A minimal synthetic reproduction is the most useful kind,
e.g. a few fake JSONL lines that show the problem.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
