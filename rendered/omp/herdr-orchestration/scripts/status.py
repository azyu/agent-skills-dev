#!/usr/bin/env python3
"""Report Herdr pane/agent state and enforce optional role-state requirements."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any


def herdr_json(*args: str) -> dict[str, Any]:
    result = subprocess.run(
        ["herdr", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "herdr command failed"
        raise RuntimeError(message)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid Herdr JSON: {error}") from error


def parse_requirement(value: str) -> tuple[str, set[str]]:
    label, separator, statuses = value.partition("=")
    allowed = {status.strip() for status in statuses.split(",") if status.strip()}
    if not separator or not label.strip() or not allowed:
        raise argparse.ArgumentTypeError("expected LABEL=STATUS[,STATUS...]")
    return label.strip(), allowed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Return normalized Herdr pane state and validate role statuses."
    )
    parser.add_argument(
        "--workspace",
        default=os.environ.get("HERDR_WORKSPACE_ID"),
        help="Herdr workspace ID; defaults to HERDR_WORKSPACE_ID.",
    )
    parser.add_argument(
        "--require",
        action="append",
        default=[],
        type=parse_requirement,
        metavar="LABEL=STATUS[,STATUS...]",
        help="Require a labeled pane to have one of the allowed agent statuses.",
    )
    args = parser.parse_args()

    if os.environ.get("HERDR_ENV") != "1":
        print(json.dumps({"ok": False, "errors": ["HERDR_ENV is not 1"]}))
        return 2
    if not args.workspace:
        print(json.dumps({"ok": False, "errors": ["workspace ID is unavailable"]}))
        return 2

    try:
        response = herdr_json("pane", "list", "--workspace", args.workspace)
        raw_panes = response["result"]["panes"]
    except (RuntimeError, KeyError, TypeError) as error:
        print(json.dumps({"ok": False, "errors": [str(error)]}))
        return 2

    panes = [
        {
            "pane_id": pane.get("pane_id"),
            "label": pane.get("label"),
            "agent": pane.get("agent"),
            "agent_status": pane.get("agent_status"),
            "cwd": pane.get("cwd"),
            "focused": pane.get("focused", False),
            "tab_id": pane.get("tab_id"),
        }
        for pane in raw_panes
    ]

    errors: list[str] = []
    requirements = []
    for label, allowed in args.require:
        matches = [pane for pane in panes if pane["label"] == label]
        observed = sorted({str(pane["agent_status"]) for pane in matches})
        requirements.append(
            {"label": label, "allowed": sorted(allowed), "observed": observed}
        )
        if not matches:
            errors.append(f"missing pane label: {label}")
        elif not any(pane["agent_status"] in allowed for pane in matches):
            errors.append(
                f"{label} status {observed} not in allowed {sorted(allowed)}"
            )

    print(
        json.dumps(
            {
                "ok": not errors,
                "workspace": args.workspace,
                "requirements": requirements,
                "panes": panes,
                "errors": errors,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
