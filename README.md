# dotfiles

Dev machine bootstrap (Ubuntu / WSL) and Claude Code guardrails.

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/samarchie/dotfiles/main/bootstrap.sh | bash
```

It checks what is installed, configured and authenticated, lists what is missing, then lets you pick what to set up:

| Key   | Action                          |
| ----- | ------------------------------- |
| ↑ / ↓ | move                            |
| enter | select / unselect item          |
| a     | select / unselect all missing   |
| i     | install selected                |
| q     | quit                            |


An optional code home sets where risq and the repos it syncs live (default `$CODE_HOME`, else `~/ui`):

```bash
curl -fsSL https://raw.githubusercontent.com/samarchie/dotfiles/main/bootstrap.sh | bash -s -- ~/code
```

From a local checkout, `./bootstrap.sh [--check] [code-home]` uses the checkout's files instead of cloning.
A log of each run is written to `$TMPDIR/bootstrap-<timestamp>.log`.

## What it sets up

- **Shell:** zsh, oh-my-zsh (agnoster theme), zsh plugins (incl. terraform: `tf`, `tfi`, `tfp`, `tfa`, ...), `tfdev`/`tftest`/`tfprod` workspace aliases, `.bash_profile` hand-off to zsh
- **Tools:** nvm + node LTS, uv, terraform, docker, postgresql client, github cli, aws cli,
  AWS Session Manager plugin, herdr, pre-commit, ripgrep, jq, fd, shellcheck, certutil
- **Docker:** daemon running and usable without sudo (on WSL, enables systemd in `/etc/wsl.conf`; restart WSL after)
- **Git:** global user, `init.defaultBranch main`, `pull.rebase false`, global gitignore for env files and bytecode,
  ed25519 SSH key added to GitHub, `gh` using SSH, commits signed with the SSH key
- **Claude Code:** cli, status line, plugins (superpowers, ponytail, caveman, i-have-adhd), Basecamp MCP, guardrails
- **Auth:** `gh auth login`, `aws configure`, `claude mcp login basecamp`
- **Hosts:** `rex.local`, `api.rex.local`, `cms.rex.local`, `catalogue.rex.local` → `127.0.0.1`
  (on WSL also the Windows hosts file, via an admin prompt)
- **Dev environment (last, needs the above):** clones or fast-forwards risq into `<code-home>/risq`, installs it with
  `uv tool install -e .`, creates the `analyst-user-role` AWS profile (`risq ec2 ssh-config`), generates and trusts
  the `rex.local` / `api.rex.local` SSL certs (on WSL, imported into the Windows user Root store), runs
  `risq dev setup` (syncs explorer-api, risk-explorer, cms, t-rex and catalogue, builds images, seeds the local db),
  then `pre-commit install` in every repo with a `.pre-commit-config.yaml`, and finally clones terraform-aws and runs
  `terraform init` in its `terraform/` dir (needs aws cli auth for the S3 backend).

Every interactive run first runs `uv tool upgrade --all` and `claude update`.

## Claude guardrails

Files in `claude/`, installed globally so they apply in every repo:

| File                  | Installed to                     | Purpose                                                      |
| --------------------- | -------------------------------- | ------------------------------------------------------------ |
| `CLAUDE.md`           | `~/.claude/CLAUDE.md`            | Global rules: secrets, databases, infrastructure             |
| `hooks/guard.py`      | `~/.claude/hooks/guard.py`       | `PreToolUse` hook that blocks rule-breaking tool calls       |
| `settings.json`       | merged into `~/.claude/settings.json` | `acceptEdits` default mode, deny rules, hook registration |
| `merge_settings.py`   | —                                | Merges `settings.json` without dropping existing config      |
| `hooks/test_guard.py` | —                                | Guard self-check, run before every install                   |

The guard blocks:

- reading, editing, copying, uploading or committing `.env` files (`.env.example`, `.env.sample`, `.env.template` are allowed)
- dumping the environment (`printenv`, bare `env`, `/proc/*/environ`)
- Postgres clients (`psql`, `pg_dump`, `pg_restore`, `pgcli`) outside `docker exec` / `docker compose exec`
- the `aws` CLI
- `risq rds forward`, `risq rds migrate` against anything but `local`, `risq aws admin`
- `terraform plan/apply/destroy/import/state/force-unlock`

Files are copied, not symlinked, so Claude editing this repo can't change the live guard.
After changing them, rerun bootstrap: the guardrails item shows as missing until the installed copies match.

Test the guard:

```bash
python3 claude/hooks/test_guard.py
```
