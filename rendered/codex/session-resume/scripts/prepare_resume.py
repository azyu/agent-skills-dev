#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


EDIT_TOOL_NAMES = {
    "apply_patch",
    "mcp__serena__create_text_file",
    "mcp__serena__replace_content",
    "mcp__serena__replace_symbol_body",
    "mcp__serena__insert_after_symbol",
    "mcp__serena__insert_before_symbol",
    "mcp__serena__rename_symbol",
}
PATCH_FILE_PATTERN = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.MULTILINE)
REQUEST_MARKER_PATTERN = re.compile(
    r"(?:My request for Codex:|## My request for Codex:)(.*)$",
    re.DOTALL,
)


@dataclass(slots=True)
class Session:
    path: Path
    session_id: str = ""
    timestamp: str = ""
    cwd: str = ""
    branch: str = ""
    thread_name: str = ""
    user_messages: list[str] = field(default_factory=list)
    assistant_messages: list[str] = field(default_factory=list)
    commands: list[str] = field(default_factory=list)
    changed_files: list[str] = field(default_factory=list)
    tool_names: list[str] = field(default_factory=list)
    score: int = 0


def normalize(value: str, limit: int | None = None) -> str:
    compact = " ".join(value.split())
    if limit and len(compact) > limit:
        return compact[: limit - 3].rstrip() + "..."
    return compact


def parse_timestamp(value: str) -> datetime:
    if not value:
        return datetime.fromtimestamp(0, timezone.utc)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.fromtimestamp(0, timezone.utc)


def timestamp_from_filename(path: Path) -> str:
    match = re.search(r"rollout-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})", path.name)
    if not match:
        return ""
    date_part, time_part = match.group(1).split("T", 1)
    return f"{date_part}T{time_part.replace('-', ':')}+00:00"


def parse_arguments(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def extract_text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""

    parts: list[str] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if isinstance(text, str):
            parts.append(text)
    return "\n".join(parts)


def extract_request(message: str) -> str:
    marker = REQUEST_MARKER_PATTERN.search(message)
    if marker:
        return marker.group(1)
    if "</environment_context>" in message:
        return message.split("</environment_context>", 1)[1]
    return message


def extract_changed_files(tool_name: str, args: dict[str, Any]) -> list[str]:
    if tool_name == "apply_patch":
        patch = args.get("patch") or args.get("input") or ""
        if isinstance(patch, str):
            return sorted({match.group(1) for match in PATCH_FILE_PATTERN.finditer(patch)})
    if tool_name in EDIT_TOOL_NAMES:
        relative_path = args.get("relative_path")
        if isinstance(relative_path, str):
            return [relative_path]
    return []


def load_session_index(codex_home: Path) -> dict[str, str]:
    index_path = codex_home / "session_index.jsonl"
    if not index_path.exists():
        return {}

    names: dict[str, str] = {}
    for line in index_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        session_id = entry.get("id")
        thread_name = entry.get("thread_name")
        if isinstance(session_id, str) and isinstance(thread_name, str):
            names[session_id] = thread_name
    return names


def parse_session(path: Path, session_index: dict[str, str]) -> Session:
    session = Session(path=path, timestamp=timestamp_from_filename(path))

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        entry_type = entry.get("type")
        payload = entry.get("payload") if isinstance(entry.get("payload"), dict) else {}

        if entry_type == "session_meta":
            session.timestamp = payload.get("timestamp") or entry.get("timestamp") or session.timestamp
            session.session_id = payload.get("id", session.session_id)
            session.cwd = payload.get("cwd", session.cwd)
            git = payload.get("git")
            if isinstance(git, dict):
                session.branch = git.get("branch", session.branch)
            continue

        if entry_type == "turn_context":
            session.cwd = payload.get("cwd", session.cwd)
            git = payload.get("git")
            if isinstance(git, dict):
                session.branch = git.get("branch", session.branch)
            continue

        if entry_type != "response_item":
            continue

        payload_type = payload.get("type")
        if payload_type == "message":
            role = payload.get("role")
            text = extract_text_from_content(payload.get("content"))
            if not text.strip():
                continue
            if role == "user":
                session.user_messages.append(text)
            elif role == "assistant":
                session.assistant_messages.append(text)
            continue

        if payload_type == "function_call":
            tool_name = payload.get("name")
            if isinstance(tool_name, str):
                session.tool_names.append(tool_name)
            args = parse_arguments(payload.get("arguments"))
            command = args.get("cmd") or args.get("command")
            if isinstance(command, str) and command.strip():
                session.commands.append(command.strip())
            if isinstance(tool_name, str):
                session.changed_files.extend(extract_changed_files(tool_name, args))

    session.thread_name = session_index.get(session.session_id, session.path.stem)
    session.changed_files = sorted(set(session.changed_files))
    return session


def collect_session_paths(codex_home: Path) -> list[Path]:
    paths = list((codex_home / "sessions").rglob("rollout-*.jsonl"))
    archived = codex_home / "archived_sessions"
    if archived.exists():
        paths.extend(archived.rglob("rollout-*.jsonl"))
    return paths


def score_session(session: Session, query_terms: set[str], cwd: str) -> int:
    score = 0
    haystack = "\n".join(
        [
            session.cwd,
            session.branch,
            session.thread_name,
            "\n".join(session.user_messages[-4:]),
            "\n".join(session.assistant_messages[-4:]),
            "\n".join(session.commands[-20:]),
            "\n".join(session.changed_files),
        ]
    ).lower()

    for term in query_terms:
        if term and term in haystack:
            score += 8

    if cwd and session.cwd:
        cwd_path = Path(cwd).resolve()
        try:
            if Path(session.cwd).resolve() == cwd_path:
                score += 80
            elif cwd_path.name and cwd_path.name in Path(session.cwd).parts:
                score += 30
        except OSError:
            pass

    if session.changed_files:
        score += 10
    if session.commands:
        score += 4

    age_hours = (
        datetime.now(timezone.utc) - parse_timestamp(session.timestamp).astimezone(timezone.utc)
    ).total_seconds() / 3600
    if age_hours < 24:
        score += 30
    elif age_hours < 168:
        score += 15
    return score


def summarize_session(session: Session, detail: bool) -> str:
    dt = parse_timestamp(session.timestamp)
    lines = [
        f"### {dt.isoformat()} `{session.path}`",
        f"- score: {getattr(session, 'score', 0)}",
        f"- cwd: `{session.cwd or 'unknown'}`",
        f"- branch: `{session.branch or 'unknown'}`",
        f"- thread: {normalize(session.thread_name, 160)}",
    ]

    if session.user_messages:
        request = normalize(extract_request(session.user_messages[-1]), 420)
        lines.append(f"- latest user request: {request}")
    if session.changed_files:
        lines.append("- changed files: " + ", ".join(f"`{path}`" for path in session.changed_files[:12]))
    if session.commands:
        lines.append("- recent commands:")
        lines.extend(f"  - `{normalize(command, 180)}`" for command in session.commands[-8:])

    if detail:
        lines.append("- recent assistant outputs:")
        for message in session.assistant_messages[-3:]:
            lines.append(f"  - {normalize(message, 360)}")
        lines.append("- recent user messages:")
        for message in session.user_messages[-3:]:
            lines.append(f"  - {normalize(extract_request(message), 360)}")

    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Find and compact relevant local Codex sessions for a session-resume subagent."
    )
    parser.add_argument("--codex-home", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--cwd", default=str(Path.cwd()))
    parser.add_argument("--query", default="")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--limit", type=int, default=6)
    parser.add_argument("--detail", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    session_index = load_session_index(args.codex_home)
    query_terms = {term.lower() for term in re.findall(r"[\w./-]{3,}", args.query)}
    since = datetime.now(timezone.utc) - timedelta(days=args.days)

    sessions: list[Session] = []
    for path in collect_session_paths(args.codex_home):
        try:
            if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < since:
                continue
        except OSError:
            continue
        session = parse_session(path, session_index)
        if parse_timestamp(session.timestamp).astimezone(timezone.utc) < since:
            continue
        session.score = score_session(session, query_terms, args.cwd)
        sessions.append(session)

    sessions.sort(
        key=lambda item: (
            item.score,
            parse_timestamp(item.timestamp).timestamp(),
        ),
        reverse=True,
    )
    selected = sessions[: max(args.limit, 1)]

    print("# Session Resume Candidates")
    print()
    print(f"- cwd filter: `{args.cwd}`")
    print(f"- query: {args.query or '(none)'}")
    print(f"- scanned sessions: {len(sessions)}")
    print()

    if not selected:
        print("No matching sessions found.")
        return 0

    for session in selected:
        print(summarize_session(session, args.detail))
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
