#!/usr/bin/env bash
#
# bootstrap.sh — dev machine setup: nvm, zsh/oh-my-zsh, plugins, claude skills.
# Usage: ./bootstrap.sh [path-to-repo-checkout]
#
set -euo pipefail
REPO_DIR="${1:-t-rex}"

LOG_FILE="${TMPDIR:-/tmp}/bootstrap-$(date +%Y%m%d-%H%M%S).log"

log()  { printf '[%(%H:%M:%S)T] %s\n' -1 "$*" | tee -a "$LOG_FILE"; }
log "Log file saving to $LOG_FILE"
die()  { log "ERROR: $*"; exit 1; }
trap 'die "failed at line $LINENO"' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
require_cmd git
require_cmd curl

log "updating repo checkout: $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" checkout main
  git -C "$REPO_DIR" fetch -p
  git -C "$REPO_DIR" pull
else
  log "skip repo update, not found: $REPO_DIR"
fi

log "installing nvm"
if [ -d "$HOME/.nvm" ]; then
  log "skip nvm install, already present"
else
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install --lts

log "installing zsh + oh-my-zsh"
sudo apt-get update -y
sudo apt-get install -y zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
  log "skip oh-my-zsh install, already present"
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

log "configuring .zshrc"
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' ~/.zshrc
grep -q '^DEFAULT_USER=' ~/.zshrc || echo 'DEFAULT_USER="$(whoami)"' >> ~/.zshrc

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
log "installing zsh plugins"
clone_plugin() {
  local url=$1 dest=$2
  if [ -d "$dest" ]; then
    log "skip clone, already present: $dest"
  else
    git clone --depth 1 "$url" "$dest"
  fi
}
clone_plugin https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_plugin https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
clone_plugin https://github.com/MichaelAquilina/zsh-you-should-use "$ZSH_CUSTOM/plugins/you-should-use"

sed -i 's/^plugins=.*/plugins=(git aws docker docker-compose zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)/' ~/.zshrc

log "installing uv"
if command -v uv >/dev/null 2>&1; then
  log "skip uv install, already present"
else
  curl -fsSL https://astral.sh/uv/install.sh | sh
fi

log "configuring git"
if git config --global --get user.name >/dev/null 2>&1; then
  log "skip git user.name, already set"
else
  git config --global user.name "Sam Archie"
fi
if git config --global --get user.email >/dev/null 2>&1; then
  log "skip git user.email, already set"
else
  git config --global user.email "sam.archie@urbanintelligence.co.nz"
fi
git config --global init.defaultBranch main
git config --global pull.rebase false

log "generating ssh key"
if [ -f "$HOME/.ssh/id_ed25519" ]; then
  log "skip ssh keygen, already present"
else
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "sam.archie@urbanintelligence.co.nz" -f "$HOME/.ssh/id_ed25519" -N ""
  log "add this public key to GitHub: https://github.com/settings/keys"
  cat "$HOME/.ssh/id_ed25519.pub"
fi

log "installing terraform"
if command -v terraform >/dev/null 2>&1; then
  log "skip terraform install, already present"
else
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update -y
  sudo apt-get install -y terraform
fi

log "installing docker"
if command -v docker >/dev/null 2>&1; then
  log "skip docker install, already present"
else
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$(whoami)"
  log "docker installed, log out/in for group membership to take effect"
fi

log "installing claude code cli"
if command -v claude >/dev/null 2>&1; then
  log "skip claude cli install, already present"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

log "adding claude plugin marketplaces"
add_marketplace() { claude plugin marketplace add "$1" 2>&1 | tee -a "$LOG_FILE" || true; }
add_marketplace https://github.com/obra/Superpowers.git
add_marketplace https://github.com/DietrichGebert/ponytail.git
add_marketplace https://github.com/juliusbrussee/caveman.git
add_marketplace https://github.com/blader/humanizer.git

log "installing claude plugins"
install_plugin() { claude plugin install "$1" 2>&1 | tee -a "$LOG_FILE" || true; }
install_plugin superpowers@superpowers-dev
install_plugin ponytail@ponytail
install_plugin caveman@caveman
install_plugin humanizer@humanizer

log "bootstrap complete. Log: $LOG_FILE"
