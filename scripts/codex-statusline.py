"""Serve the shared workspace status line to the Codex CLI over MCP."""

import json
import os
from pathlib import Path
import subprocess
import sys

URI = "ui://workspace-statusline/footer"
SNAPSHOT = "com.openai/codex-statusline-state"
FORMATTER = Path(__file__).resolve().with_name("statusline.sh")
TOOL = {
    "name": "statusline",
    "title": "Workspace status line",
    "description": "Show workspace and session data in the Codex footer.",
    "inputSchema": {"type": "object", "properties": {}},
    "_meta": {"openai/ui": {
        "entrypoints": [{"type": "statusline", "resourceUri": URI}],
    }},
}


def rate_limits(account):
    snapshots = account.get("rate_limits", [])
    snapshot = next((item for item in snapshots if item["limit_id"] == "codex"), None)
    if snapshot is None and len(snapshots) == 1:
        snapshot = snapshots[0]
    if snapshot is None:
        return {}

    limits = {}
    for key in ("primary_limit", "secondary_limit"):
        window = snapshot.get(key)
        if window and (label := {300: "five_hour", 10080: "seven_day"}.get(
            window.get("window_minutes")
        )):
            limits[label] = {"used_percentage": window["used_percent"]}
    return limits


def git_diff(cwd):
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "-C", cwd, "diff", "--numstat",
             "--no-ext-diff", "--no-textconv", "HEAD", "--"],
            capture_output=True, text=True, errors="replace", timeout=0.2,
            check=True,
        )
    except (OSError, subprocess.SubprocessError):
        return {}

    added = removed = 0
    for line in result.stdout.splitlines():
        counts = line.split("\t", 2)
        if len(counts) == 3 and all(count.isdecimal() for count in counts[:2]):
            added += int(counts[0])
            removed += int(counts[1])
    return {"total_lines_added": added, "total_lines_removed": removed}


def render(snapshot):
    thread = snapshot.get("thread", {})
    cwd = thread.get("workspace", {}).get("cwd") or os.getcwd()
    model = thread.get("model", {})
    model_name = model.get("display_name") or "Codex"
    if reasoning := model.get("reasoning_level"):
        model_name = f"{model_name} ({reasoning})"
    usage = thread.get("usage", {})
    context = dict(usage.get("context", {}))
    if total := usage.get("total"):
        context.update(
            total_input_tokens=total["total_input_tokens"],
            total_output_tokens=total["output_tokens"],
            current_usage={
                "cache_read_input_tokens": total["cache_read_input_tokens"],
                "cache_creation_input_tokens": total["cache_write_input_tokens"],
                "input_tokens": total["other_input_tokens"],
            },
        )
    data = {
        "cwd": cwd,
        "model": {"display_name": model_name},
        "context_window": context,
        "cost": (usage.get("cost") or {}) | git_diff(cwd),
        "rate_limits": rate_limits(snapshot.get("account", {})),
    }

    try:
        output = subprocess.run(
            ["bash", str(FORMATTER)], input=json.dumps(data),
            capture_output=True, text=True, timeout=0.6, check=True,
            env=os.environ | {"NO_COLOR": "1"},
        ).stdout
    except (OSError, subprocess.SubprocessError):
        output = f"{cwd} │ {model_name}"

    segments = []
    for line in output.splitlines():
        segments.extend(line.split(" │ "))
    return {
        "type": "row",
        "props": {"gap": 2, "wrap": "wrap"},
        "children": segments,
    }


def respond(method, params):
    if method == "initialize":
        return {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}, "resources": {}},
            "serverInfo": {"name": "workspace-statusline", "version": "1.0"},
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [TOOL]}
    if method == "resources/list":
        return {"resources": [{"name": "footer", "uri": URI}]}
    if method == "resources/templates/list":
        return {"resourceTemplates": []}
    if method == "resources/read":
        if params.get("uri") != URI:
            raise ValueError("Unknown resource")
        state = params.get("_meta", {}).get(SNAPSHOT, {})
        return {"contents": [{
            "uri": URI,
            "mimeType": "application/json",
            "text": json.dumps(render(state), ensure_ascii=False),
        }]}
    raise KeyError(method)


def main():
    for line in sys.stdin:
        request_id = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict) or not isinstance(request.get("method"), str):
                raise ValueError("Invalid request")
            if "id" not in request:
                continue
            request_id = request["id"]
            result = respond(request["method"], request.get("params", {}))
            response = {"result": result}
        except json.JSONDecodeError:
            response = {"error": {"code": -32700, "message": "Parse error"}}
        except KeyError:
            response = {"error": {"code": -32601, "message": "Method not found"}}
        except (TypeError, ValueError, AttributeError):
            response = {"error": {"code": -32602, "message": "Invalid parameters"}}
        print(json.dumps({"jsonrpc": "2.0", "id": request_id} | response), flush=True)


if __name__ == "__main__":
    main()
