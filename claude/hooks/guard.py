#!/usr/bin/env python3
"""Claude Code PreToolUse guard.

Blocks (exit 2, reason on stderr):
- reading, editing, copying, uploading or committing .env files (.env.example/.sample/.template/.dist are fine)
- dumping the process environment (printenv, bare env, /proc/*/environ)
- Postgres clients outside `docker exec` / `docker compose exec`, so only local Docker DBs are reachable
- the aws CLI
- RDS port forwarding, non-local migrations, admin role, and terraform commands that touch real state
"""
import json
import os
import re
import subprocess
import sys

SAFE_ENV_SUFFIXES = {"example", "sample", "template", "dist"}
ENV_TOKEN = re.compile(r"(?<![\w.-])\.env(?:\.[\w-]+)*(?![\w.-])")
SEGMENT_SPLIT = re.compile(r"&&|\|\||[;|&\n`()]|\$\(")
DB_CLIENT = re.compile(r"(?<![\w-])(psql|pg_dump|pg_dumpall|pg_restore|pgcli)(?![\w-])")
DOCKER_EXEC = re.compile(r"^(sudo\s+)?(docker\s+(compose\s+)?exec|docker-compose\s+exec)\b")
AWS_CLI = re.compile(r"^(sudo\s+)?(env\s+)?(\w+=\S*\s+)*aws(\s|$)")
BLOCKED_COMMANDS = [
    (re.compile(r"\brisq\s+rds\s+forward\b"), "RDS port forwarding reaches shared/prod databases"),
    (re.compile(r"\brisq\s+rds\s+migrate\s+(?!local\b)"), "only `risq rds migrate local` is allowed"),
    (re.compile(r"\brisq\s+aws\s+admin\b"), "the elevated admin role is for the user only"),
    (re.compile(r"\bterraform\b[^;&|\n]*\s(plan|apply|destroy|import|state|force-unlock)\b"),
     "terraform commands that touch real AWS state are for the user only"),
    (re.compile(r"/proc/[^/\s]+/environ"), "the process environment may hold secrets"),
]


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


def check_bash(command, cwd):
    for match in ENV_TOKEN.findall(command):
        if is_env_file(match):
            return f"command references {match}, which may hold secrets"

    for segment in SEGMENT_SPLIT.split(command):
        segment = segment.strip()
        if re.fullmatch(r"(sudo\s+)?(printenv(\s.*)?|env)", segment):
            return "dumping the environment may expose secrets"
        if AWS_CLI.match(segment):
            return "aws CLI calls are for the user only"
        if DB_CLIENT.search(segment) and not DOCKER_EXEC.match(segment):
            return ("database clients may only run inside a local Docker container, "
                    "e.g. `docker compose exec db psql ...`")

    for pattern, reason in BLOCKED_COMMANDS:
        if pattern.search(command):
            return reason

    if re.search(r"\bgit\b[^;&|\n]*\scommit\b", command):
        env_files = staged_env_files(command, cwd)
        if env_files:
            return f"commit would include env files: {', '.join(env_files)}"
    return None


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input") or {}
    if data.get("tool_name") == "Bash":
        reason = check_bash(tool_input.get("command", ""), data.get("cwd") or os.getcwd())
    else:
        reason = check_paths(tool_input)
    if reason:
        print(f"Blocked by ~/.claude/hooks/guard.py: {reason}. Ask the user to do this themselves.", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
