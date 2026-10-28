#!/usr/bin/env python3
"""Merge dotfiles claude/settings.json into ~/.claude/settings.json without dropping existing keys.

Usage: merge_settings.py <source> <target> [--check]
Permission lists are unioned; other permission keys (e.g. defaultMode) take the source value.
Hook entries are added, or replace an existing entry that runs the same hook commands.
  --check  exit 0 if target already matches the merge result, else 1
"""
import json
import os
import shutil
import sys
import time


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def merge(source, target):
    merged = dict(target)
    permissions = dict(merged.get("permissions", {}))
    for key, value in source.get("permissions", {}).items():
        if isinstance(value, list):
            existing = list(permissions.get(key, []))
            permissions[key] = existing + [rule for rule in value if rule not in existing]
        else:
            permissions[key] = value
    merged["permissions"] = permissions

    # an entry running the same hook commands is replaced, so a changed matcher doesn't add a duplicate hook
    hooks = dict(merged.get("hooks", {}))
    for event, entries in source.get("hooks", {}).items():
        existing = list(hooks.get(event, []))
        for entry in entries:
            same = [i for i, old in enumerate(existing) if old.get("hooks") == entry.get("hooks")]
            if same:
                existing[same[0]] = entry
            else:
                existing.append(entry)
        hooks[event] = existing
    merged["hooks"] = hooks
    return merged


def main():
    source_path, target_path = sys.argv[1], sys.argv[2]
    source, target = load(source_path), load(target_path)
    merged = merge(source, target)
    if "--check" in sys.argv:
        sys.exit(0 if merged == target else 1)
    if merged == target:
        return
    if os.path.exists(target_path):
        shutil.copy2(target_path, f"{target_path}.bak.{int(time.time())}")
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    with open(target_path, "w") as f:
        json.dump(merged, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
