#!/bin/sh
# Install mbgc dev prerequisites on Debian/Ubuntu Linux.
# Usage: sh scripts/install-deps.sh [--yes] [--prod] [--check]
#   --yes    Non-interactive: install all core tools without prompting
#   --prod   Also install prod-only tools (Terraform, gcloud)
#   --check  Show which tools are installed/missing, then exit
set -eu

GO_VERSION="1.25.0"

# ── Flags ─────────────────────────────────────────────────────────────────────
OPT_YES=0
OPT_PROD=0
OPT_CHECK=0

for _arg in "$@"; do
    case "$_arg" in
        --yes|-y)  OPT_YES=1 ;;
        --prod)    OPT_PROD=1 ;;
        --check)   OPT_CHECK=1 ;;
        --help|-h)
            sed -n '2,4p' "$0" | sed 's/^# //'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$_arg" >&2; exit 1 ;;
    esac
done

# ── Output helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

info() { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$*"; }
step() { printf "\n${BLUE}▶${NC} %s\n" "$*"; }
skip() { printf "  skip  %s\n" "$*"; }
miss() { printf "${RED}✗${NC} %s — not found\n" "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    if [ "$OPT_YES" = "1" ]; then return 0; fi
    printf '  Install %s? [y/N] ' "$1"
    read -r _yn
    case "$_yn" in y|Y|yes|YES) return 0 ;; esac
    return 1
}

# OS codename without requiring lsb_release
codename() {
    if has lsb_release; then
        lsb_release -cs
    else
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s' "$VERSION_CODENAME"
    fi
}

apt_arch() { dpkg --print-architecture; }

go_arch() {
    case "$(uname -m)" in
        x86_64)  printf 'amd64' ;;
        aarch64) printf 'arm64' ;;
        *) printf 'Unsupported arch: %s\n' "$(uname -m)" >&2; exit 1 ;;
    esac
}

# ── Preflight ─────────────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Linux" ]; then
    printf 'This script targets Linux only.\n' >&2; exit 1
fi
if [ "$(id -u)" = "0" ]; then
    printf 'Run as a regular user; sudo is invoked internally.\n' >&2; exit 1
fi
if ! has apt-get; then
    printf 'apt-get not found — requires Debian/Ubuntu.\n' >&2; exit 1
fi

printf "\n${BLUE}mbgc — dev prerequisites installer${NC}\n"
printf 'Platform: Linux  Flags: yes=%s prod=%s check=%s\n' "$OPT_YES" "$OPT_PROD" "$OPT_CHECK"

# ── Check mode ────────────────────────────────────────────────────────────────
if [ "$OPT_CHECK" = "1" ]; then
    printf '\nTool status:\n'
    for _t in go docker bun supabase gh tmux jq curl git; do
        if has "$_t"; then
            _v="$($_t --version 2>/dev/null | head -1 || printf '?')"
            info "$_t — $_v"
        else
            miss "$_t"
        fi
    done
    if [ "$OPT_PROD" = "1" ]; then
        for _t in terraform gcloud; do
            if has "$_t"; then
                _v="$($_t --version 2>/dev/null | head -1 || printf '?')"
                info "$_t — $_v"
            else
                miss "$_t"
            fi
        done
    fi
    exit 0
fi

# ── Base apt packages ─────────────────────────────────────────────────────────
step "Base packages (curl, git, tmux, jq)"
sudo apt-get update -qq
_base=""
for _p in curl git tmux jq; do
    if has "$_p"; then skip "$_p"; else _base="$_base $_p"; fi
done
if [ -n "$_base" ]; then
    # shellcheck disable=SC2086
    sudo apt-get install -y $_base
    info "Installed:$_base"
fi

# ── Docker ────────────────────────────────────────────────────────────────────
step "Docker (required for local Supabase)"
if has docker; then
    skip "docker — $(docker --version)"
elif confirm "Docker"; then
    sudo apt-get install -y ca-certificates gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$(apt_arch)" "$(codename)" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    warn "Docker installed. Run 'newgrp docker' or log out+in for group membership."
fi

# ── Go ────────────────────────────────────────────────────────────────────────
step "Go $GO_VERSION"
if has go; then
    skip "go — $(go version)"
elif confirm "Go $GO_VERSION"; then
    _tar="go${GO_VERSION}.linux-$(go_arch).tar.gz"
    curl -fsSL "https://go.dev/dl/${_tar}" -o "/tmp/${_tar}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${_tar}"
    rm "/tmp/${_tar}"
    if ! printf '%s' "${PATH:-}" | grep -q '/usr/local/go/bin'; then
        printf '\nexport PATH="$PATH:/usr/local/go/bin"\n' >> "$HOME/.zshenv.local"
        export PATH="$PATH:/usr/local/go/bin"
        warn "Added /usr/local/go/bin to ~/.zshenv.local — reload shell after setup."
    fi
    info "Go $GO_VERSION → /usr/local/go"
fi

# ── Bun ───────────────────────────────────────────────────────────────────────
step "Bun (JS runtime for web/)"
if has bun; then
    skip "bun — $(bun --version)"
elif confirm "Bun"; then
    curl -fsSL https://bun.sh/install | sh
    export PATH="$HOME/.bun/bin:$PATH"
    info "Bun → ~/.bun/bin/bun"
fi

# ── Supabase CLI ──────────────────────────────────────────────────────────────
step "Supabase CLI"
if has supabase; then
    skip "supabase — $(supabase --version)"
elif confirm "Supabase CLI"; then
    case "$(uname -m)" in
        x86_64)  _sarch="linux_amd64" ;;
        aarch64) _sarch="linux_arm64" ;;
        *) printf 'Unsupported arch: %s\n' "$(uname -m)" >&2; exit 1 ;;
    esac
    _surl="$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest \
        | grep 'browser_download_url' \
        | grep "${_sarch}.deb" \
        | head -1 \
        | cut -d'"' -f4)"
    if [ -z "$_surl" ]; then
        warn "Could not resolve release URL — install manually: https://supabase.com/docs/guides/cli"
    else
        curl -fsSL "$_surl" -o /tmp/supabase.deb
        sudo dpkg -i /tmp/supabase.deb
        rm /tmp/supabase.deb
        info "Supabase CLI installed"
    fi
fi

# ── GitHub CLI ────────────────────────────────────────────────────────────────
step "GitHub CLI (gh)"
if has gh; then
    skip "gh — $(gh --version | head -1)"
elif confirm "GitHub CLI"; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
        "$(apt_arch)" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
    info "gh installed"
fi

# ── Prod tools (optional) ─────────────────────────────────────────────────────
if [ "$OPT_PROD" = "1" ]; then
    step "Terraform (prod)"
    if has terraform; then
        skip "terraform — $(terraform version | head -1)"
    elif confirm "Terraform"; then
        curl -fsSL https://apt.releases.hashicorp.com/gpg \
            | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        printf 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s main\n' \
            "$(codename)" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
        sudo apt-get update -qq
        sudo apt-get install -y terraform
        info "Terraform installed"
    fi

    step "gcloud SDK (prod)"
    if has gcloud; then
        skip "gcloud — $(gcloud --version | head -1)"
    elif confirm "gcloud CLI"; then
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
            | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
        printf 'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main\n' \
            | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
        sudo apt-get update -qq
        sudo apt-get install -y google-cloud-cli
        info "gcloud installed"
    fi
fi

# ── Git branch check ──────────────────────────────────────────────────────────
step "Git branch"
_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'none')"
if [ "$_branch" = "dev" ]; then
    skip "already on dev"
elif [ "$_branch" = "none" ]; then
    warn "Not inside a git repo — skipping branch check"
else
    warn "Current branch: $_branch (expected: dev)"
    if confirm "Switch to dev branch"; then
        git checkout dev
        info "Switched to dev"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n${GREEN}Done.${NC} Next steps:\n"
printf '  1. Reload shell:       exec $SHELL\n'
printf '  2. If Docker was new:  newgrp docker\n'
printf '  3. First-time setup:   make setup-local\n'
printf '  4. Start dev:          make dev\n\n'
