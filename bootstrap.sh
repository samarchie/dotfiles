#!/usr/bin/env bash
#
# bootstrap.sh — dev machine setup: checks what is installed/configured/authed,
# shows what is missing, then lets you pick missing pieces to set up from an
# arrow-key menu (↑/↓ move, enter toggle, a toggle all, i install selected, q quit).
# Usage: ./bootstrap.sh [--check] [path-to-repo-checkout]
#   --check  show status only, change nothing (exits 1 if anything is missing)
#
set -uo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi
REPO_DIR="${1:-t-rex}"

LOG_FILE="${TMPDIR:-/tmp}/bootstrap-$(date +%Y%m%d-%H%M%S).log"

log()  { printf '[%(%H:%M:%S)T] %s\n' -1 "$*" | tee -a "$LOG_FILE"; }
die()  { log "ERROR: $*"; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
ask()  { local reply; read -r -p "$1 [y/N] " reply; [[ $reply =~ ^[Yy] ]]; }

has git  || die "required command not found: git"
has curl || die "required command not found: curl"

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
ITEMS=(nvm node zsh ohmyzsh zsh_plugins uv git_config terraform docker postgresql
       claude statusline claude_plugins basecamp_mcp basecamp_auth gh gh_auth aws aws_auth herdr)
declare -A LABEL=(
  [nvm]="nvm"
  [node]="node LTS (via nvm)"
  [zsh]="zsh"
  [ohmyzsh]="oh-my-zsh + .zshrc config"
  [zsh_plugins]="zsh plugins"
  [uv]="uv"
  [git_config]="git global config"
  [terraform]="terraform"
  [docker]="docker"
  [postgresql]="postgresql"
  [claude]="claude code cli"
  [statusline]="claude status line"
  [claude_plugins]="claude plugins (${!CLAUDE_PLUGINS[*]})"
  [basecamp_mcp]="basecamp mcp added to claude"
  [basecamp_auth]="basecamp mcp authenticated"
  [gh]="github cli"
  [gh_auth]="github cli authenticated"
  [aws]="aws cli"
  [aws_auth]="aws cli authenticated"
  [herdr]="herdr"
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
  grep -q '^export GIT_AUTHOR_NAME=' ~/.zshrc || echo "export GIT_AUTHOR_NAME='Sam Archie'" >> ~/.zshrc
}

# nvm plugin loads ~/.nvm in zsh; nvm's installer only edits whichever profile existed when it ran
ZSH_PLUGINS_LINE="plugins=(git aws docker docker-compose nvm zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)"
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

check_uv()      { has uv; }
install_uv()    { curl -fsSL https://astral.sh/uv/install.sh | sh; }

check_git_config() {
  git config --global --get user.name >/dev/null &&
  git config --global --get user.email >/dev/null &&
  [ "$(git config --global --get init.defaultBranch)" = main ] &&
  [ "$(git config --global --get pull.rebase)" = false ]
}
install_git_config() {
  git config --global --get user.name >/dev/null || git config --global user.name "Sam Archie"
  git config --global --get user.email >/dev/null || git config --global user.email "sam.archie@urbanintelligence.co.nz"
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

check_basecamp_mcp()   { has claude && claude mcp get basecamp >/dev/null 2>&1; }
install_basecamp_mcp() { claude mcp add --scope user --transport http basecamp https://mcp.basecamp.com/mcp; }

check_basecamp_auth()   { has claude && claude mcp get basecamp 2>&1 | grep -q "Connected"; }
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

check_aws()     { has aws; }
install_aws()   { curl -fsSL https://awscli.amazonaws.com/v2/install.sh | bash; }

check_aws_auth()   { has aws && aws sts get-caller-identity >/dev/null 2>&1; }
install_aws_auth() { aws configure; }

check_herdr()   { has herdr; }
install_herdr() { curl -fsSL https://herdr.dev/install.sh | sh; }

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
  for id in "${ITEMS[@]}"; do
    if [ "${STATUS[$id]}" = ok ]; then echo "  $OK ${LABEL[$id]}"; else echo "  $NO ${LABEL[$id]}"; fi
  done
  echo
}

declare -A PICKED FAILED
draw_menu() {
  local i id box line
  printf '\e[H\e[2J'
  echo "↑/↓ move · enter select/unselect · a select/unselect all · i install selected · q quit"
  echo
  for i in "${!ITEMS[@]}"; do
    id=${ITEMS[$i]}
    if [ "${STATUS[$id]}" = ok ]; then box=" $OK "
    elif [ -n "${PICKED[$id]:-}" ]; then box="[x]"
    else box="[ ]"; fi
    line="$box ${LABEL[$id]}"
    [ -n "${FAILED[$id]:-}" ] && line+=" ${RED}(failed last run, see log)${RST}"
    if [ "$i" -eq "$CURSOR" ]; then echo "${REV}> $line${RST}"; else echo "  $line"; fi
  done
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
      $'\e[B') [ "$CURSOR" -lt $((${#ITEMS[@]} - 1)) ] && CURSOR=$((CURSOR + 1)) ;;
      "")  # enter
        id=${ITEMS[$CURSOR]}
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

log "Log file saving to $LOG_FILE"

if [ "$CHECK_ONLY" = 0 ] && [ -d "$REPO_DIR/.git" ] && ask "Update repo checkout $REPO_DIR to latest main?"; then
  git -C "$REPO_DIR" checkout main && git -C "$REPO_DIR" fetch -p && git -C "$REPO_DIR" pull
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

CURSOR=0
tput civis; trap 'tput cnorm' EXIT
while menu; do
  tput cnorm
  printf '\e[H\e[2J'
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
  read -rsp "Press enter to return to the menu" _
  tput civis
done

tput cnorm
printf '\e[H\e[2J'
print_status
log "bootstrap complete. Log: $LOG_FILE"
[ ${#MISSING[@]} -eq 0 ]
