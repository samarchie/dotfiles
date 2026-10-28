#!/usr/bin/env python3
"""Claude Code PreToolUse guard.

Blocks (exit 2, reason on stderr):
- reading, editing, copying, uploading or committing .env files (.env.example/.sample/.template/.dist are fine)
- dumping the process environment (printenv, bare env, /proc/*/environ)
- Postgres clients outside `docker exec` / `docker compose exec`, so only local Docker DBs are reachable
- the aws CLI
- RDS port forwarding, non-local migrations, admin role, and terraform commands that touch real state

Slack MCP tools (plugin or claude.ai connector): reads are allowed without a prompt,
anything else (send, react, canvas, list or file changes) always asks the user first.
"""
import json
import os
import re
import shlex
import subprocess
import sys

SAFE_ENV_SUFFIXES = {"example", "sample", "template", "dist"}
# a backslash before .env means a regex like '\.env', not a file
ENV_TOKEN = re.compile(r"(?<![\w.\\-])\.env(?:\.[\w-]+)*(?![\w.-])")
SEGMENT_SPLIT = re.compile(r"&&|\|\||[;|&\n`()]|\$\(")
# prefixes that still run the command after them
WRAPPERS = re.compile(r"^(?:(?:sudo|env|time|nohup|exec|command|xargs)(?:\s+-\S+)*\s+|timeout\s+\S+\s+|\w+=\S*\s+)*")
SUBSHELL = re.compile(r"^(?:ba|z|da)?sh\s+(?:-\w+\s+)*-\w*c\s+|^eval\s+")
# these only print or search text, so naming a DB client in their arguments doesn't run it
TEXT_TOOLS = {"grep", "egrep", "fgrep", "rg", "ag", "echo", "printf", "git"}
DB_CLIENT = re.compile(r"(?<![\w-])(psql|pg_dump|pg_dumpall|pg_restore|pgcli)(?![\w-])")
DOCKER_EXEC = re.compile(r"^(docker\s+(compose\s+)?exec|docker-compose\s+exec)\b")
BLOCKED_COMMANDS = [
    (re.compile(r"^aws(\s|$)"), "aws CLI calls are for the user only"),
    (re.compile(r"^risq\s+rds\s+forward\b"), "RDS port forwarding reaches shared/prod databases"),
    (re.compile(r"^risq\s+rds\s+migrate\s+(?!local\b)"), "only `risq rds migrate local` is allowed"),
    (re.compile(r"^risq\s+aws\s+admin\b"), "the elevated admin role is for the user only"),
    (re.compile(r"^terraform\b.*\s(plan|apply|destroy|import|state|force-unlock)\b"),
     "terraform commands that touch real AWS state are for the user only"),
]
SLACK_TOOL = re.compile(r"^mcp__.*slack.*__slack_(\w+)$", re.IGNORECASE)
SLACK_READ = re.compile(r"^(read|search|list)_\w+$|^get_reactions$")


def is_env_file(path):
    base = os.path.basename(path.rstrip("/"))
    if not re.fullmatch(r"\.env(\.[\w.-]+)?", base):
        return False
    return base == ".env" or base.rsplit(".", 1)[-1] not in SAFE_ENV_SUFFIXES


def check_paths(tool_input):
    for key in ("file_path", "path", "notebook_path", "glob"):
        value = tool_input.get(key)
        if isinstance(value, str) and is_env_file(value):
            return f"{value} is an env file and may hold secrets"
    return None


def staged_env_files(command, cwd):
    def names(*args):
        result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
        return result.stdout.split() if result.returncode == 0 else []

    files = names("diff", "--cached", "--name-only")
    if re.search(r"\s(-a|--all|-[a-zA-Z]*a[a-zA-Z]*)\b", command):
        files += names("diff", "--name-only")
    return [f for f in files if is_env_file(f)]


def subshell_script(segment):
    """The script passed to `bash -c` / `sh -c` / `eval`, or None."""
    match = SUBSHELL.match(segment)
    if not match:
        return None
    try:
        args = shlex.split(segment[match.end():])
    except ValueError:
        return segment[match.end():]
    return " ".join(args) if segment.startswith("eval") else (args[0] if args else "")


def check_segment(segment, cwd):
    if re.fullmatch(r"(sudo\s+)?(printenv(\s.*)?|env)", segment):
        return "dumping the environment may expose secrets"
    command = WRAPPERS.sub("", segment)
    script = subshell_script(command)
    if script is not None:
        return check_bash(script, cwd)
    for pattern, reason in BLOCKED_COMMANDS:
        if pattern.match(command):
            return reason
    name = command.split(maxsplit=1)[0] if command else ""
    if name not in TEXT_TOOLS and DB_CLIENT.search(command) and not DOCKER_EXEC.match(command):
        return ("database clients may only run inside a local Docker container, "
                "e.g. `docker compose exec db psql ...`")
    return None


def check_bash(command, cwd):
    for match in ENV_TOKEN.findall(command):
        if is_env_file(match):
            return f"command references {match}, which may hold secrets"
    if re.search(r"/proc/[^/\s]+/environ", command):
        return "the process environment may hold secrets"

    for segment in SEGMENT_SPLIT.split(command):
        reason = check_segment(segment.strip(), cwd)
        if reason:
            return reason

    if re.search(r"\bgit\b[^;&|\n]*\scommit\b", command):
        env_files = staged_env_files(command, cwd)
        if env_files:
            return f"commit would include env files: {', '.join(env_files)}"
    return None


def slack_decision(tool_name):
    match = SLACK_TOOL.match(tool_name)
    if not match:
        return None
    if SLACK_READ.match(match.group(1)):
        return "allow", "reading Slack is allowed"
    return "ask", f"slack_{match.group(1)} changes Slack, so the user must confirm it"


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input") or {}
    slack = slack_decision(data.get("tool_name", ""))
    if slack:
        decision, reason = slack
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": decision, "permissionDecisionReason": reason,
        }}))
        return
    if data.get("tool_name") == "Bash":
        reason = check_bash(tool_input.get("command", ""), data.get("cwd") or os.getcwd())
    else:
        reason = check_paths(tool_input)
    if reason:
        print(f"Blocked by ~/.claude/hooks/guard.py: {reason}. Ask the user to do this themselves.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
