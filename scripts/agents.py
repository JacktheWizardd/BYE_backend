#!/usr/bin/env python3
"""Shared activity board so Claude Code and Codex can see what the other is doing in this checkout.

State lives in the git-ignored `.agents/` folder:
  .agents/log.jsonl    one JSON line per event (start, update, done, blocked, touch, note)
  .agents/state.json   each agent's current task, status and claimed files, plus read markers

Commands (agent is `claude` or `codex`):
  start  <agent> "task" [--files a b]   claim a task (warns if the other agent claims the same files)
  update <agent> "progress note"         mid-task progress
  blocked <agent> "what you need"        flag that you are waiting on someone
  done   <agent> "summary"               finish and release claimed files
  note   <agent> "message for the other agent"
  touch  <agent> <file> | --hook         record a file being edited (--hook reads Claude hook JSON on stdin)
  inbox  <agent> [--hook]                what the OTHER agent did since you last checked
  status                                 everyone's current task and the last 15 events
"""
import argparse
import datetime
import fcntl
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIR = ROOT / ".agents"
LOG = DIR / "log.jsonl"
STATE = DIR / "state.json"
AGENTS = ("claude", "codex")


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


class Board:
    """Holds an exclusive lock on the state file for the duration of a command."""

    def __enter__(self):
        DIR.mkdir(exist_ok=True)
        self.lock = open(DIR / ".lock", "w")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        try:
            self.state = json.loads(STATE.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            self.state = {}
        self.state.setdefault("agents", {})
        self.state.setdefault("seen", {})
        return self

    def __exit__(self, *exc):
        tmp = STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, indent=2))
        os.replace(tmp, STATE)
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.lock.close()

    def log(self, agent, kind, text, files=None):
        entry = {"at": now(), "agent": agent, "kind": kind, "text": text}
        if files:
            entry["files"] = files
        with LOG.open("a") as f:
            f.write(json.dumps(entry) + "\n")
        return entry

    def agent(self, name):
        return self.state["agents"].setdefault(name, {"status": "idle", "task": "", "files": [], "updated": now()})


def entries():
    if not LOG.exists():
        return []
    out = []
    for line in LOG.read_text().splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def rel(path):
    p = pathlib.Path(path)
    try:
        return str(p.resolve().relative_to(ROOT))
    except (ValueError, OSError):
        return str(path)


def describe(e):
    files = f" [{', '.join(e['files'][:6])}{'…' if len(e.get('files', [])) > 6 else ''}]" if e.get("files") else ""
    return f"{e['at']}  {e['agent']:<6} {e['kind']:<7} {e['text']}{files}"


def overlap(board, me, files):
    warnings = []
    for name, info in board.state["agents"].items():
        if name == me or info.get("status") not in ("working", "blocked"):
            continue
        shared = sorted(set(files) & set(info.get("files", [])))
        if shared:
            warnings.append(f"WARNING: {name} is working on {', '.join(shared)} ({info.get('task', '')}). Coordinate before editing.")
    return warnings


def cmd_status(_):
    with Board() as board:
        if not board.state["agents"]:
            print("No agent activity yet.")
        for name, info in sorted(board.state["agents"].items()):
            files = f" — files: {', '.join(info.get('files', [])[:10])}" if info.get("files") else ""
            print(f"{name}: {info.get('status')} · {info.get('task') or '(no task)'} · since {info.get('updated')}{files}")
    recent = entries()[-15:]
    if recent:
        print("\nRecent activity:")
        for e in recent:
            print("  " + describe(e))


def set_status(args, status, kind):
    with Board() as board:
        info = board.agent(args.agent)
        files = [rel(f) for f in (getattr(args, "files", None) or [])]
        for w in overlap(board, args.agent, files):
            print(w)
        if kind == "start":
            info.update(task=args.text, files=files)
        elif files:
            info["files"] = sorted(set(info.get("files", [])) | set(files))
        if kind == "done":
            info["files"] = []
        info.update(status=status, updated=now())
        board.log(args.agent, kind, args.text, files or None)
    print(f"Logged {kind} for {args.agent}.")


def cmd_touch(args):
    path = args.file
    if args.hook:
        try:
            payload = json.load(sys.stdin)
        except json.JSONDecodeError:
            return
        tool_input = payload.get("tool_input") or {}
        path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not path:
        return
    path = rel(path)
    if path.startswith(".agents/"):
        return
    with Board() as board:
        info = board.agent(args.agent)
        warnings = overlap(board, args.agent, [path])
        if path not in info.get("files", []):
            info.setdefault("files", []).append(path)
            if info.get("status") != "working":
                info.update(status="working", task=info.get("task") or "editing files")
            board.log(args.agent, "touch", f"editing {path}", [path])
        info["updated"] = now()
    if warnings and args.hook:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": " ".join(warnings)}}))
    elif warnings:
        print("\n".join(warnings))


def cmd_inbox(args):
    with Board() as board:
        all_entries = entries()
        start = board.state["seen"].get(args.agent, 0)
        new = [e for e in all_entries[start:] if e.get("agent") != args.agent]
        board.state["seen"][args.agent] = len(all_entries)
        others = {n: i for n, i in board.state["agents"].items() if n != args.agent and i.get("status") in ("working", "blocked")}
    lines = []
    for name, info in others.items():
        files = f"; files: {', '.join(info.get('files', [])[:8])}" if info.get("files") else ""
        lines.append(f"{name} is {info.get('status')}: {info.get('task')}{files}")
    if new:
        lines.append("New activity from other agents:")
        lines += ["  " + describe(e) for e in new[-20:]]
    if not lines:
        return
    text = "Agent coordination board (scripts/agents.py):\n" + "\n".join(lines)
    print(text)  # from a SessionStart/UserPromptSubmit hook, stdout is added to Claude's context


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    for name, status in [("start", "working"), ("update", "working"), ("blocked", "blocked"), ("done", "idle"), ("note", None)]:
        s = sub.add_parser(name)
        s.add_argument("agent", choices=AGENTS)
        s.add_argument("text")
        s.add_argument("--files", nargs="*")
        s.set_defaults(status=status)
    t = sub.add_parser("touch")
    t.add_argument("agent", choices=AGENTS)
    t.add_argument("file", nargs="?")
    t.add_argument("--hook", action="store_true")
    i = sub.add_parser("inbox")
    i.add_argument("agent", choices=AGENTS)
    i.add_argument("--hook", action="store_true")
    sub.add_parser("status")
    args = p.parse_args()
    if args.command == "status":
        cmd_status(args)
    elif args.command == "touch":
        cmd_touch(args)
    elif args.command == "inbox":
        cmd_inbox(args)
    elif args.command == "note":
        with Board() as board:
            board.agent(args.agent)["updated"] = now()
            board.log(args.agent, "note", args.text)
        print(f"Logged note for {args.agent}.")
    else:
        set_status(args, args.status, args.command)


if __name__ == "__main__":
    main()
