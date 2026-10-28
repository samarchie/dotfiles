#!/usr/bin/env bash
#
# bootstrap.sh — dev machine setup: checks what is installed/configured/authed,
# shows what is missing, then lets you pick missing pieces to set up from an
# arrow-key menu (↑/↓ move, enter toggle, a toggle all, i install selected, q quit).
# Usage: curl -fsSL https://raw.githubusercontent.com/samarchie/dotfiles/main/bootstrap.sh | bash
#        curl -fsSL .../bootstrap.sh | bash -s -- [--check] [code-home]
#        ./bootstrap.sh [--check] [code-home]   (from a checkout, uses its local files)
#   code-home  where risq and the repos it syncs live (default $CODE_HOME, else ~/code)
#   --check  show status only, change nothing (exits 1 if anything is missing)
#
set -uo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi
# exported so risq uses the same CODE_HOME; an environment value wins over risq's own env file
CODE_HOME="$(realpath -m "${1:-${CODE_HOME:-$HOME/ui}}")"
export CODE_HOME
RISQ_DIR="$CODE_HOME/risq"
TF_DIR="$CODE_HOME/terraform-aws/terraform"
RISQ_REPOS=(risq explorer-api risk-explorer cms t-rex catalogue)

LOG_FILE="${TMPDIR:-/tmp}/bootstrap-$(date +%Y%m%d-%H%M%S).log"

log()  { printf '[%(%H:%M:%S)T] %s\n' -1 "$*" | tee -a "$LOG_FILE"; }
die()  { log "ERROR: $*"; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
is_wsl() { grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

REX_HOSTS=(rex.local api.rex.local cms.rex.local catalogue.rex.local)
WIN_HOSTS=/mnt/c/Windows/System32/drivers/etc/hosts
SSH_KEY="$HOME/.ssh/id_ed25519"
GLOBAL_GITIGNORE=(".env" ".env.*" "!.env.example" "!.env.sample" "!.env.template" "__pycache__/" "*.py[cod]" ".DS_Store")

has git  || die "required command not found: git"
has curl || die "required command not found: curl"
has unzip || die "required command not found: unzip"

if [ -t 1 ]; then
  OK=$'\e[32m✓\e[0m'; NO=$'\e[31m✗\e[0m'; REV=$'\e[7m'; RED=$'\e[31m'; RST=$'\e[0m'
else
  OK='[ok]'; NO='[missing]'; REV=''; RED=''; RST=''
fi

# installers drop binaries here; make them visible to later checks in this run
export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
load_nvm() { [ -s "$NVM_DIR/nvm.sh" ] || return 1; set +u; . "$NVM_DIR/nvm.sh"; set -u; }

# set in main: this checkout when run as a file, else a temp clone (curl | bash has no files beside it)
DOTFILES_REPO=https://github.com/samarchie/dotfiles.git
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
DOTFILES_TMP=""
# menu draws on the alternate screen so it never scrolls the terminal; installs run on the normal screen
menu_screen_on()  { printf '\e[?1049h\e[?25l'; }
menu_screen_off() { printf '\e[?25h\e[?1049l'; }
cleanup() { [ -t 1 ] && menu_screen_off; [ -n "$DOTFILES_TMP" ] && rm -rf "$DOTFILES_TMP"; }
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
declare -A ZSH_PLUGINS=(
  [zsh-autosuggestions]=https://github.com/zsh-users/zsh-autosuggestions
  [zsh-syntax-highlighting]=https://github.com/zsh-users/zsh-syntax-highlighting
  [zsh-history-substring-search]=https://github.com/zsh-users/zsh-history-substring-search
  [you-should-use]=https://github.com/MichaelAquilina/zsh-you-should-use
)

# plugin -> marketplace repo
declare -A CLAUDE_PLUGINS=(
  [superpowers@superpowers-dev]=https://github.com/obra/Superpowers.git
  [ponytail@ponytail]=https://github.com/DietrichGebert/ponytail.git
  [caveman@caveman]=https://github.com/juliusbrussee/caveman.git
  [i-have-adhd@i-have-adhd]=https://github.com/ayghri/i-have-adhd
)

# Each item has check_<id> (exit 0 = done) and install_<id>. Order matters: later items may need earlier ones.
ITEMS=(wsl_interop nvm node zsh ohmyzsh zsh_plugins zsh_aliases uv cli_tools git_config global_gitignore terraform docker docker_running postgresql
       claude statusline claude_plugins claude_guardrails basecamp_mcp basecamp_auth
       gh gh_auth ssh_key git_signing aws aws_auth ssm_plugin herdr rex_hosts pre_commit
       risq env_files aws_profile ssl_certs risq_dev_setup pre_commit_hooks
       terraform_aws)  # these last: they need docker, ssh, terraform and aws cli + auth
declare -A LABEL=(
  [nvm]="nvm"
  [node]="node LTS (via nvm)"
  [zsh]="zsh"
  [ohmyzsh]="oh-my-zsh + .zshrc config"
  [zsh_plugins]="zsh plugins"
  [zsh_aliases]="terraform workspace aliases (tfdev tftest tfprod)"
  [uv]="uv"
  [wsl_interop]="wsl can run windows programs (browser, powershell)"
  [cli_tools]="cli tools (ripgrep jq fd shellcheck certutil, wslu on wsl)"
  [git_config]="git global config"
  [global_gitignore]="global gitignore (env files, bytecode)"
  [terraform]="terraform"
  [docker]="docker"
  [docker_running]="docker daemon running and usable without sudo"
  [postgresql]="postgresql"
  [claude]="claude code cli"
  [statusline]="claude status line"
  [claude_plugins]="claude plugins (${!CLAUDE_PLUGINS[*]})"
  [claude_guardrails]="claude guardrails (global CLAUDE.md, guard hook, deny rules)"
  [basecamp_mcp]="basecamp mcp added to claude"
  [basecamp_auth]="basecamp mcp authenticated"
  [gh]="github cli"
  [gh_auth]="github cli authenticated"
  [ssh_key]="github ssh key (git over ssh)"
  [git_signing]="git commits signed with ssh key"
  [aws]="aws cli"
  [aws_auth]="aws cli authenticated"
  [ssm_plugin]="aws session manager plugin"
  [herdr]="herdr"
  [rex_hosts]="hosts entries (${REX_HOSTS[*]})"
  [pre_commit]="pre-commit"
  [aws_profile]="aws profile analyst-user-role (risq ec2 ssh-config)"
  [ssl_certs]="rex.local ssl certs generated and trusted"
  [pre_commit_hooks]="pre-commit hooks installed in repos"
  [terraform_aws]="terraform-aws cloned and initialised ($TF_DIR)"
  [risq]="risq cloned, up to date and installed ($RISQ_DIR)"
  [env_files]="repo env files (catalogue cms explorer-api risq risk-explorer)"
  [risq_dev_setup]="risq dev setup (repos synced into $CODE_HOME)"
)

check_nvm()     { [ -s "$NVM_DIR/nvm.sh" ]; }
install_nvm()   { curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash; }

check_node()    { load_nvm && has node; }
install_node()  { load_nvm; nvm install --lts; }

check_zsh()     { has zsh; }
install_zsh()   { sudo apt-get update -y; sudo apt-get install -y zsh; }

check_ohmyzsh() { [ -d "$HOME/.oh-my-zsh" ]; }
install_ohmyzsh() {
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  # chsh isn't available to run as my usual user
  cat > ~/.bash_profile << 'EOF'
if [ -x "$(command -v zsh)" ] && [ -z "$ZSH_VERSION" ] && [[ $- == *i* ]]; then
    export SHELL=$(command -v zsh)
    exec $(command -v zsh) -l
fi
EOF

  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' ~/.zshrc
  grep -q '^DEFAULT_USER=' ~/.zshrc || echo 'DEFAULT_USER="$(whoami)"' >> ~/.zshrc
}

# nvm plugin loads ~/.nvm in zsh; nvm's installer only edits whichever profile existed when it ran
ZSH_PLUGINS_LINE="plugins=(git aws docker docker-compose nvm terraform zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)"
check_zsh_plugins() {
  local p
  for p in "${!ZSH_PLUGINS[@]}"; do [ -d "$ZSH_CUSTOM/plugins/$p" ] || return 1; done
  grep -qxF "$ZSH_PLUGINS_LINE" ~/.zshrc
}
install_zsh_plugins() {
  local p
  for p in "${!ZSH_PLUGINS[@]}"; do
    [ -d "$ZSH_CUSTOM/plugins/$p" ] || git clone --depth 1 "${ZSH_PLUGINS[$p]}" "$ZSH_CUSTOM/plugins/$p"
  done
  sed -i "s/^plugins=.*/$ZSH_PLUGINS_LINE/" ~/.zshrc
}

# workspace switchers from the terraform-aws README
ZSH_ALIASES=(
  'alias tfdev="terraform workspace select development"'
  'alias tftest="terraform workspace select test"'
  'alias tfprod="terraform workspace select production"'
)
check_zsh_aliases() {
  local line
  for line in "${ZSH_ALIASES[@]}"; do grep -qxF -- "$line" ~/.zshrc || return 1; done
}
install_zsh_aliases() {
  local line
  for line in "${ZSH_ALIASES[@]}"; do grep -qxF -- "$line" ~/.zshrc || echo "$line" >> ~/.zshrc; done
}

check_uv()      { has uv; }
install_uv()    { curl -fsSL https://astral.sh/uv/install.sh | sh; }

check_git_config() {
  git config --global --get user.name >/dev/null &&
  git config --global --get user.email >/dev/null &&
  [ "$(git config --global --get init.defaultBranch)" = main ] &&
  [ "$(git config --global --get pull.rebase)" = false ]
}
install_git_config() {
  local key value
  for key in user.name user.email; do
    git config --global --get "$key" >/dev/null && continue
    read -r -p "git $key: " value
    [ -n "$value" ] || { log "git $key is required"; return 1; }
    git config --global "$key" "$value"
  done
  git config --global init.defaultBranch main
  git config --global pull.rebase false
}

check_terraform() { has terraform; }
install_terraform() {
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -y
  sudo apt-get install -y terraform
}

check_docker()  { has docker; }
install_docker() {
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$(whoami)"
  log "docker installed, log out/in for group membership to take effect"
}

check_docker_running() { docker info >/dev/null 2>&1; }
install_docker_running() {
  if is_wsl && ! grep -qx 'systemd=true' /etc/wsl.conf 2>/dev/null; then
    if grep -qx '\[boot\]' /etc/wsl.conf 2>/dev/null; then
      sudo sed -i '/^\[boot\]$/a systemd=true' /etc/wsl.conf
    else
      printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
    fi
    log "enabled systemd in /etc/wsl.conf: run 'wsl.exe --shutdown' from Windows, reopen, rerun bootstrap"
  fi
  [[ " $(id -nG) " == *" docker "* ]] || sudo usermod -aG docker "$(whoami)"
  sudo systemctl enable --now docker 2>/dev/null || sudo service docker start
  docker info >/dev/null 2>&1 || log "docker group not active in this shell yet: log out/in (or restart WSL) and rerun"
}

# other binfmt registrations (e.g. a qemu/binfmt container) can wipe WSL's handler, leaving
# "exec format error" for every .exe; systemd-binfmt re-registers it from /usr/lib/binfmt.d
check_wsl_interop() { ! is_wsl || /mnt/c/Windows/System32/cmd.exe /c exit 0 >/dev/null 2>&1; }
install_wsl_interop() {
  sudo systemctl restart systemd-binfmt 2>/dev/null ||
    echo ':WSLInterop:M::MZ::/init:PF' | sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null
  check_wsl_interop
}

check_cli_tools() {
  local tool
  for tool in rg jq fd shellcheck certutil; do has "$tool" || return 1; done
  ! is_wsl || has wslview
}
install_cli_tools() {
  sudo apt-get update -y
  sudo apt-get install -y ripgrep jq fd-find shellcheck libnss3-tools
  # wslview lets gh, aws sso and others open the Windows browser
  ! is_wsl || sudo apt-get install -y wslu
  # ubuntu names the binary fdfind
  has fd || { mkdir -p "$HOME/.local/bin"; ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"; }
}

global_gitignore_path() {
  local path
  path=$(git config --global --get core.excludesFile || echo "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore")
  echo "${path/#\~/$HOME}"
}
check_global_gitignore() {
  local line file; file=$(global_gitignore_path)
  for line in "${GLOBAL_GITIGNORE[@]}"; do grep -qxF -- "$line" "$file" 2>/dev/null || return 1; done
}
install_global_gitignore() {
  local line file; file=$(global_gitignore_path)
  mkdir -p "$(dirname "$file")"; touch "$file"
  for line in "${GLOBAL_GITIGNORE[@]}"; do grep -qxF -- "$line" "$file" || echo "$line" >> "$file"; done
}

check_postgresql()   { has psql; }
install_postgresql() { sudo apt-get install -y postgresql postgresql-contrib; }

check_claude()  { has claude; }
install_claude(){ curl -fsSL https://claude.ai/install.sh | bash; }

check_statusline()   { grep -qs '"statusLine"' "$HOME/.claude/settings.json"; }
install_statusline() { curl -fsSL https://statusline-community.zoniixyt.workers.dev/i/wqJr9DNjzw.sh | bash; }

check_claude_plugins() {
  local p
  for p in "${!CLAUDE_PLUGINS[@]}"; do
    grep -qs "\"$p\"" "$HOME/.claude/plugins/installed_plugins.json" || return 1
  done
}
install_claude_plugins() {
  local p
  for p in "${!CLAUDE_PLUGINS[@]}"; do
    claude plugin marketplace add "${CLAUDE_PLUGINS[$p]}" || true  # errors if already added
    claude plugin install "$p"
  done
}

# copied, not symlinked, so Claude editing dotfiles can't change the live guard; edits need a reinstall
# settings are merged because ~/.claude/settings.json holds other config
declare -A GUARDRAIL_FILES=(
  ["$DOTFILES_DIR/claude/CLAUDE.md"]="$HOME/.claude/CLAUDE.md"
  ["$DOTFILES_DIR/claude/hooks/guard.py"]="$HOME/.claude/hooks/guard.py"
)
check_claude_guardrails() {
  local src
  for src in "${!GUARDRAIL_FILES[@]}"; do
    [ ! -L "${GUARDRAIL_FILES[$src]}" ] && cmp -s "$src" "${GUARDRAIL_FILES[$src]}" || return 1
  done
  python3 "$DOTFILES_DIR/claude/merge_settings.py" "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json" --check
}
install_claude_guardrails() {
  local src dest
  python3 "$DOTFILES_DIR/claude/hooks/test_guard.py"
  mkdir -p "$HOME/.claude/hooks"
  for src in "${!GUARDRAIL_FILES[@]}"; do
    dest=${GUARDRAIL_FILES[$src]}
    if [ -f "$dest" ] && [ ! -L "$dest" ] && ! cmp -s "$src" "$dest"; then
      cp "$dest" "$dest.bak.$(date +%s)"
      log "backed up existing $dest"
    fi
    rm -f "$dest"  # drop old symlinks so cp doesn't write through into dotfiles
    cp "$src" "$dest"
  done
  python3 "$DOTFILES_DIR/claude/merge_settings.py" "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
}

check_basecamp_mcp()   { has claude && claude mcp get basecamp >/dev/null 2>&1; }
install_basecamp_mcp() { claude mcp add --scope user --transport http basecamp https://mcp.basecamp.com/mcp; }

check_basecamp_auth()   { has claude && [[ $(claude mcp get basecamp 2>&1) == *Connected* ]]; }
install_basecamp_auth() { claude mcp login basecamp; }

check_gh()      { has gh; }
install_gh() {
  has wget || { sudo apt-get update -y; sudo apt-get install -y wget; }
  sudo mkdir -p -m 755 /etc/apt/keyrings
  local out; out=$(mktemp)
  wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg < "$out" > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo mkdir -p -m 755 /etc/apt/sources.list.d
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y gh
}

check_gh_auth()   { has gh && gh auth status >/dev/null 2>&1; }
install_gh_auth() { gh auth login; }

ssh_key_body() { awk '{print $2}' "$SSH_KEY.pub"; }
gh_scope() { [[ $(gh auth status 2>&1) == *"'$1'"* ]] || gh auth refresh -h github.com -s "$1"; }
check_ssh_key() {
  [ -f "$SSH_KEY" ] && [ "$(gh config get git_protocol 2>/dev/null)" = ssh ] &&
  # github always exits 1 here, so match the output instead of piping (pipefail would fail the pipe)
  [[ $(ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1) == *"successfully authenticated"* ]]
}
install_ssh_key() {
  [ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$SSH_KEY"
  gh_scope admin:public_key
  gh api user/keys --jq '.[].key' | grep -F "$(ssh_key_body)" >/dev/null || gh ssh-key add "$SSH_KEY.pub" --title "$(hostname)"
  gh config set git_protocol ssh
}

check_git_signing() {
  [ "$(git config --global --get gpg.format)" = ssh ] &&
  [ "$(git config --global --get commit.gpgsign)" = true ] &&
  [ "$(git config --global --get user.signingkey)" = "$SSH_KEY.pub" ]
}
install_git_signing() {
  gh_scope admin:ssh_signing_key
  gh api user/ssh_signing_keys --jq '.[].key' | grep -F "$(ssh_key_body)" >/dev/null ||
    gh ssh-key add "$SSH_KEY.pub" --type signing --title "$(hostname) signing"
  git config --global gpg.format ssh
  git config --global user.signingkey "$SSH_KEY.pub"
  git config --global commit.gpgsign true
}

check_aws()     { has aws; }
install_aws()   { curl -fsSL https://awscli.amazonaws.com/v2/install.sh | bash; }

check_aws_auth()   { has aws && aws sts get-caller-identity >/dev/null 2>&1; }
install_aws_auth() { aws configure; }

check_herdr()   { has herdr; }
install_herdr() { curl -fsSL https://herdr.dev/install.sh | sh; }

check_ssm_plugin() { has session-manager-plugin; }
install_ssm_plugin() {
  local arch deb
  case "$(dpkg --print-architecture)" in arm64) arch=ubuntu_arm64 ;; *) arch=ubuntu_64bit ;; esac
  deb=$(mktemp --suffix .deb)
  curl -fsSL -o "$deb" "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/$arch/session-manager-plugin.deb"
  sudo dpkg -i "$deb"
  rm -f "$deb"
}

# prints the REX_HOSTS names that $1 doesn't map; handles CRLF (Windows hosts file)
missing_hosts() {
  local host
  for host in "${REX_HOSTS[@]}"; do
    awk -v h="$host" '{ sub(/\r$/, "") } $1 !~ /^#/ { for (i = 2; i <= NF; i++) if ($i == h) f = 1 } END { exit !f }' "$1" 2>/dev/null ||
      printf '%s ' "$host"
  done
}
# WSL regenerates /etc/hosts from Windows and Windows browsers only read the Windows file, so set both
check_rex_hosts() {
  [ -z "$(missing_hosts /etc/hosts)" ] || return 1
  ! is_wsl || [ -z "$(missing_hosts "$WIN_HOSTS")" ]
}
install_rex_hosts() {
  local missing
  missing=$(missing_hosts /etc/hosts)
  [ -z "$missing" ] || printf '\n127.0.0.1 %s\n' "$missing" | sudo tee -a /etc/hosts >/dev/null
  if is_wsl; then
    missing=$(missing_hosts "$WIN_HOSTS")
    if [ -n "$missing" ]; then
      log "approve the Windows admin prompt to update the Windows hosts file"
      powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -Command Add-Content -Path \$env:SystemRoot\\System32\\drivers\\etc\\hosts -Value ''127.0.0.1 ${missing% }'''"
    fi
  fi
}

check_pre_commit()   { has pre-commit; }
install_pre_commit() { uv tool install pre-commit; }

check_risq() {
  [ -d "$RISQ_DIR/.git" ] && has risq &&
  git -C "$RISQ_DIR" fetch -q &&
  [ "$(git -C "$RISQ_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)" = 0 ]
}
install_risq() {
  if [ -d "$RISQ_DIR/.git" ]; then
    git -C "$RISQ_DIR" pull --ff-only
  else
    mkdir -p "$CODE_HOME"
    git clone git@github.com:uintel/risq.git "$RISQ_DIR"
  fi
  has risq || (cd "$RISQ_DIR" && uv tool install -e .)
}

# repo -> env file it needs; risq first because any risq command silently creates its own from the example
ENV_REPOS=(risq catalogue cms explorer-api risk-explorer)
declare -A ENV_FILES=([risq]=.env [catalogue]=.env [cms]=.env [explorer-api]=.env [risk-explorer]=.env.local)
check_env_files() {
  local repo
  for repo in "${ENV_REPOS[@]}"; do [ -s "$CODE_HOME/$repo/${ENV_FILES[$repo]}" ] || return 1; done
}
install_env_files() {
  local repo file synced=0
  for repo in "${ENV_REPOS[@]}"; do
    file="$CODE_HOME/$repo/${ENV_FILES[$repo]}"
    [ -s "$file" ] && continue
    if [ ! -d "$CODE_HOME/$repo" ] && [ "$synced" = 0 ]; then
      (cd "$RISQ_DIR" && risq dev sync)
      synced=1
    fi
    if [ -f "$CODE_HOME/$repo/.env.example" ]; then cp "$CODE_HOME/$repo/.env.example" "$file"; else touch "$file"; fi
    log "fill in $file, then save and exit the editor"
    "${EDITOR:-nano}" "$file"
  done
  check_env_files
}

# shortcut: only checks the repos were synced; `risq dev setup` exits 0 even when build or seeding fails, so read its output
check_risq_dev_setup() {
  local repo
  for repo in "${RISQ_REPOS[@]}"; do [ -d "$CODE_HOME/$repo/.git" ] || return 1; done
}
install_risq_dev_setup() { (cd "$RISQ_DIR" && risq dev setup); }

check_aws_profile()   { aws configure get role_arn --profile analyst-user-role >/dev/null 2>&1; }
install_aws_profile() { risq ec2 ssh-config; }

# nginx serves cms/catalogue with the rex.local cert, so it carries a *.rex.local SAN
declare -A SSL_CERTS=(
  [rex.local]="--san www.rex.local --san *.rex.local --san 127.0.0.1 --san ::1"
  [api.rex.local]="--san 127.0.0.1 --san ::1"
)
cert_thumbprint() { openssl x509 -noout -fingerprint -sha1 -in "$1" | cut -d= -f2 | tr -d ':'; }
cert_trusted() {
  if is_wsl; then
    [ "$(powershell.exe -NoProfile -Command "Test-Path Cert:\\CurrentUser\\Root\\$(cert_thumbprint "$1")" | tr -d '\r')" = True ]
  else
    certutil -d "sql:$HOME/.pki/nssdb" -L -n "risq-dev-$(basename "$1" .crt)" >/dev/null 2>&1
  fi
}
check_ssl_certs() {
  local domain crt
  for domain in "${!SSL_CERTS[@]}"; do
    crt="$RISQ_DIR/ssl/$domain.crt"
    [ -f "$crt" ] && openssl x509 -checkend 86400 -noout -in "$crt" >/dev/null && cert_trusted "$crt" || return 1
  done
}
install_ssl_certs() {
  local domain crt win_tmp
  for domain in "${!SSL_CERTS[@]}"; do
    crt="$RISQ_DIR/ssl/$domain.crt"
    if [ ! -f "$crt" ] || ! openssl x509 -checkend 86400 -noout -in "$crt" >/dev/null; then
      # SAN flags are word-split on purpose; set -f stops *.rex.local globbing
      # shellcheck disable=SC2086
      (set -f; cd "$RISQ_DIR" && risq dev generate-ssl-cert --domain "$domain" ${SSL_CERTS[$domain]})
    fi
    cert_trusted "$crt" && continue
    if is_wsl; then
      # Import-Certificate can't read \\wsl.localhost paths reliably, so copy to Windows temp first
      win_tmp=$(wslpath "$(powershell.exe -NoProfile -Command '$env:TEMP' | tr -d '\r')")
      cp "$crt" "$win_tmp/$domain.crt"
      log "approve the Windows prompt to trust $domain"
      powershell.exe -NoProfile -Command "Import-Certificate -FilePath \"\$env:TEMP\\$domain.crt\" -CertStoreLocation Cert:\\CurrentUser\\Root" >/dev/null
    else
      (cd "$RISQ_DIR" && risq dev import-ssl-cert "ssl/$domain.crt")
    fi
  done
}

pre_commit_repos() {
  local dir
  for dir in "$CODE_HOME"/*/; do
    [ -f "$dir.pre-commit-config.yaml" ] && [ -d "$dir.git" ] && echo "${dir%/}"
  done
}
check_pre_commit_hooks() {
  local repo
  for repo in $(pre_commit_repos); do grep -qs pre-commit "$repo/.git/hooks/pre-commit" || return 1; done
}
install_pre_commit_hooks() {
  local repo
  for repo in $(pre_commit_repos); do
    grep -qs pre-commit "$repo/.git/hooks/pre-commit" || (cd "$repo" && pre-commit install)
  done
}

# init reads the S3 backend, so it needs the aws cli logged in
check_terraform_aws() { [ -d "$TF_DIR/.terraform/providers" ]; }
install_terraform_aws() {
  [ -d "$CODE_HOME/terraform-aws/.git" ] || git clone git@github.com:uintel/terraform-aws.git "$CODE_HOME/terraform-aws"
  terraform -chdir="$TF_DIR" init
}

# menu and status list are alphabetical by label; installs still follow ITEMS (dependency) order
mapfile -t DISPLAY < <(for id in "${ITEMS[@]}"; do printf '%s\t%s\n' "${LABEL[$id]}" "$id"; done | sort -f | cut -f2)

declare -A STATUS
run_checks() {
  local id
  MISSING=()
  for id in "${ITEMS[@]}"; do
    if "check_$id"; then STATUS[$id]=ok; else STATUS[$id]=missing; MISSING+=("$id"); fi
  done
}
print_status() {
  local id
  echo
  for id in "${DISPLAY[@]}"; do
    if [ "${STATUS[$id]}" = ok ]; then echo "  $OK ${LABEL[$id]}"; else echo "  $NO ${LABEL[$id]}"; fi
  done
  echo
}

declare -A PICKED=() FAILED=()
draw_menu() {
  local i id box label suffix width end
  local help="↑↓ move · enter toggle · a all · i install · q quit"
  local rows cols visible
  # tput inside $(...) can't see the terminal and falls back to 24x80, so ask the tty directly
  read -r rows cols < <(stty size </dev/tty 2>/dev/null || echo "24 80")
  # 3 fixed lines (help, "more above", "more below") and one spare so the terminal never scrolls
  visible=$((rows - 4)); [ "$visible" -lt 3 ] && visible=3
  [ "$CURSOR" -lt "$TOP" ] && TOP=$CURSOR
  [ "$CURSOR" -ge $((TOP + visible)) ] && TOP=$((CURSOR - visible + 1))
  end=$((TOP + visible)); [ "$end" -gt ${#DISPLAY[@]} ] && end=${#DISPLAY[@]}

  printf '\e[H\e[J'
  echo "${help:0:cols}"
  if [ "$TOP" -gt 0 ]; then echo "  ↑ $TOP more"; else echo; fi
  for ((i = TOP; i < end; i++)); do
    id=${DISPLAY[$i]}
    if [ "${STATUS[$id]}" = ok ]; then box=" $OK "
    elif [ -n "${PICKED[$id]:-}" ]; then box="[x]"
    else box="[ ]"; fi
    suffix=""; [ -n "${FAILED[$id]:-}" ] && suffix=" ${RED}(failed, see log)${RST}"
    # truncate so long labels don't wrap onto extra rows
    width=$((cols - 6)); [ -n "$suffix" ] && width=$((width - 17))
    label=${LABEL[$id]:0:width}
    if [ "$i" -eq "$CURSOR" ]; then echo "${REV}> $box $label${RST}$suffix"; else echo "  $box $label$suffix"; fi
  done
  [ "$end" -lt ${#DISPLAY[@]} ] && printf '  ↓ %d more' $((${#DISPLAY[@]} - end))
}

# returns 0 when the user asks to install the picked items, 1 on quit
menu() {
  local key rest id
  while true; do
    draw_menu
    IFS= read -rsn1 key
    if [ "$key" = $'\e' ]; then IFS= read -rsn2 -t 0.1 rest; key+=$rest; fi
    case "$key" in
      $'\e[A') [ "$CURSOR" -gt 0 ] && CURSOR=$((CURSOR - 1)) ;;
      $'\e[B') [ "$CURSOR" -lt $((${#DISPLAY[@]} - 1)) ] && CURSOR=$((CURSOR + 1)) ;;
      "")  # enter
        id=${DISPLAY[$CURSOR]}
        if [ "${STATUS[$id]}" != ok ]; then
          if [ -n "${PICKED[$id]:-}" ]; then unset "PICKED[$id]"; else PICKED[$id]=1; fi
        fi ;;
      a|A)  # select all missing, or unselect all if they're already selected
        if [ ${#PICKED[@]} -eq ${#MISSING[@]} ]; then
          PICKED=()
        else
          for id in "${MISSING[@]}"; do PICKED[$id]=1; done
        fi ;;
      i|I) [ ${#PICKED[@]} -gt 0 ] && return 0 ;;
      q|Q) return 1 ;;
    esac
  done
}

main() {
  log "Log file saving to $LOG_FILE"
  trap cleanup EXIT

  if [ ! -f "$DOTFILES_DIR/claude/settings.json" ]; then
    DOTFILES_TMP=$(mktemp -d)
    DOTFILES_DIR=$DOTFILES_TMP
    log "fetching dotfiles from $DOTFILES_REPO"
    git clone -q --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR" || die "could not clone $DOTFILES_REPO"
  fi

  if [ "$CHECK_ONLY" = 0 ]; then
    log "updating uv tools and claude"
    has uv && uv tool upgrade --all
    has claude && claude update
  fi

  log "checking machine setup"
  run_checks
  print_status

  if [ ${#MISSING[@]} -eq 0 ]; then
    log "everything is set up"
    exit 0
  fi
  [ "$CHECK_ONLY" = 1 ] && exit 1
  if [ ! -t 0 ] || [ ! -t 1 ]; then log "not a terminal, can't show the menu; rerun interactively"; exit 1; fi

  CURSOR=0; TOP=0
  menu_screen_on
  while menu; do
    menu_screen_off
    # walk ITEMS, not PICKED, so dependencies install in order
    for id in "${ITEMS[@]}"; do
      [ -n "${PICKED[$id]:-}" ] || continue
      log "setting up: ${LABEL[$id]}"
      # subshell + set -e: stop this item at its first failing command, then carry on with the rest
      ( set -e; "install_$id" )
      if [ $? -ne 0 ]; then log "FAILED: ${LABEL[$id]}"; FAILED[$id]=1; else unset "FAILED[$id]"; fi
    done
    PICKED=()
    log "re-checking machine setup"
    run_checks
    menu_screen_on
  done

  menu_screen_off
  print_status
  log "bootstrap complete. Log: $LOG_FILE"
  [ ${#MISSING[@]} -eq 0 ]
}

# under `curl | bash` stdin is this script, so prompts and installers must read the terminal instead
if { : </dev/tty; } 2>/dev/null; then main "$@" </dev/tty; else main "$@"; fi
