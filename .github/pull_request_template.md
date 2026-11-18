## What and why

<!-- What does this change, and what problem does it solve? Link the issue: "Closes #12". -->

## How I tested it

<!-- e.g. `--selftest` output, steps in the app, screenshots from `--snapshot` (demo data, not your real board). -->

## Checklist

- [ ] `PITWALL_DATA_DIR=$(mktemp -d) .build/debug/Pitwall --selftest` passes
- [ ] Reader/merge/backlog-file changes have a new check in `SelfTest.swift`
- [ ] No network calls, no writes to any agent's files, backlog edits stay surgical ([ground rules](https://github.com/aidarkazybekov/pitwall/blob/main/CONTRIBUTING.md#ground-rules))
- [ ] Screenshots contain no private data
