## What and why

<!-- What does this change, and what problem does it solve? Link the issue: "Closes #12". -->

## How I tested it

<!-- e.g. `--selftest` output, steps in the app, screenshots from `--snapshot` (demo data, not your real board). -->

## Checklist

- [ ] `CLAUDEBOARD_DATA_DIR=$(mktemp -d) .build/debug/ClaudeBoard --selftest` passes
- [ ] Parser/merge/backlog-file changes have a new check in `SelfTest.swift`
- [ ] No network calls, no writes to `~/.claude`, backlog edits stay surgical ([ground rules](https://github.com/aidarkazybekov/claude-board/blob/main/CONTRIBUTING.md#ground-rules))
- [ ] Screenshots contain no private data
