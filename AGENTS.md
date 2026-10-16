# Working alongside another agent (Claude Code + Codex)

Claude Code and Codex may both be working in this checkout at the same time. They coordinate through
`scripts/agents.py`, which keeps a shared board in the git-ignored `.agents/` folder. Use your own name
(`claude` or `codex`) in every command.

- **Before starting a task**, run `python3 -I scripts/agents.py inbox <you>` to see what the other agent did
  and is doing. Then claim the work with
  `python3 -I scripts/agents.py start <you> "short task description" --files <paths you expect to edit>`.
  If it prints a WARNING that the other agent holds one of those files, don't edit that file. Pick other
  work, or log a `note` and wait.
- **While working**, log meaningful progress with `python3 -I scripts/agents.py update <you> "what changed"`.
  Use `blocked <you> "what you need"` when waiting, and `note <you> "message"` to tell the other agent something.
- **When finished**, run `python3 -I scripts/agents.py done <you> "summary, tests run"`. This releases your files.
- `python3 -I scripts/agents.py status` shows both agents and the last 15 events.
- Claude Code does some of this automatically through hooks in `.claude/settings.json`: it reads its inbox on
  every prompt and logs each file it edits. Codex runs the commands above by hand, at the start and end of each task.
- Never edit, delete or reset `.agents/` by hand, and never revert the other agent's uncommitted changes.

# Local Mac testing workflow

- After completing native Mac app changes, run `./scripts/build-test-app.sh` to update `test/BYE Test.app` with the latest source.
- The user opens the visible `test` folder to test development builds. Use this stable app location when sharing the latest build.
- Relaunch the updated test app after finishing Mac development so the user can test immediately. Close an older running BYE development instance first.
- Keep generated test apps out of Git. This workflow is local testing; publishing requires a separate user request.

# Area guides

- The browser app migrated to `../BYE_website/apps/web/`; read that repository’s `AGENTS.md` and `apps/web/AGENTS.md`. The old `apps/web/README.md` is a migration pointer; its older area guide is historical.
- The website lives in a separate repository (`../BYE_website`) with its own `AGENTS.md`.
