# Global rules

These apply in every repo. Repo CLAUDE.md files may be stricter, never looser.
`~/.claude/hooks/guard.py` enforces most of them; if it blocks a command, don't try to work around it — ask the user.

## Secrets

- Never read, print, edit, copy, upload or commit `.env` files (`.env`, `.env.local`, `.env.production`, ...).
  `.env.example`, `.env.sample` and `.env.template` are fine.
- Never dump the environment (`printenv`, bare `env`, `/proc/*/environ`) or read secrets
  (AWS Secrets Manager, `~/.aws/credentials`, `config.yaml` DB credentials).
- Before committing, check staged files contain no secrets.

## Databases

- Never connect to a dev, test, production or other shared database, and never use their credentials.
- Only use local Docker databases, and only via `docker exec <container> ...` or `docker compose exec <service> ...`.
- Never run `risq rds forward`, `risq rds migrate` against anything but `local`, or `aws ssm start-session`.

## Slack

- Reading Slack (channels, threads, search, profiles, canvases, lists, reactions) is fine.
- Anything that changes Slack — sending or scheduling a message, replying in a thread, reacting, creating or
  editing canvases, lists or conversations, uploading files — needs the user's confirmation first.
  Show the exact message or change before asking.

## Infrastructure

- Never run the `aws` CLI, `terraform plan/apply/destroy/import/state`, or `risq aws admin`.
  Suggest the command to the user instead.
