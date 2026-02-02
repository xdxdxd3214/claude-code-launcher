#!/usr/bin/env bash
#
# claude-code-launcher uninstaller
# https://github.com/ash3in/claude-code-launcher
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/ash3in/claude-code-launcher/main/uninstall.sh | bash
#

set -e


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

success() { printf "${GREEN}✓ ${NC}%s\n" "$1"; }
warn()    { printf "${YELLOW}⚠️ ${NC}%s\n" "$1"; }
error()   { printf "${RED}✗ ${NC}%s\n" "$1"; }
info()    { printf "${CYAN}ℹ ${NC}%s\n" "$1"; }

print_banner() {
    echo ""
    printf "${RED}${BOLD}"
    echo "  ╭─────────────────────────────────────────────╮"
    echo "  │                                             │"
    echo "  │   claude-code-launcher Uninstaller          │"
    echo "  │                                             │"
    echo "  ╰─────────────────────────────────────────────╯"
    printf "${NC}"
    echo ""
}

detect_shell() {
    if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        echo "zsh"
    elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == *"bash"* ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

get_shell_config() {
    local shell_type="$1"
    case "$shell_type" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

ask_yes_no() {
    local question="$1"
    local default="${2:-y}"
    local hint=""

    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    printf "${CYAN}? ${NC}${BOLD}%s${NC} %s " "$question" "$hint"
    read -r response
    response="${response:-$default}"

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

main() {
    print_banner

    local shell_type
    shell_type=$(detect_shell)
    local shell_config
    shell_config=$(get_shell_config "$shell_type")

    info "Shell config: $shell_config"
    echo ""


    if ! grep -q "claude-code-launcher START" "$shell_config" 2>/dev/null; then
        warn "claude-code-launcher not found in $shell_config"
        echo ""
        exit 0
    fi


    if ! ask_yes_no "Remove claude-code-launcher from $shell_config?"; then
        echo ""
        info "Cancelled."
        exit 0
    fi

    echo ""


    if sed -i.tmp '/# claude-code-launcher START/,/# claude-code-launcher END/d' "$shell_config"; then
        rm -f "${shell_config}.tmp"
        success "Removed claude-code-launcher from $shell_config"
    else
        error "Failed to remove claude-code-launcher"
        exit 1
    fi


    if [[ -f "$HOME/.claude-token" ]]; then
        echo ""
        if ask_yes_no "Remove stored token (~/.claude-token)?" "n"; then
            rm -f "$HOME/.claude-token"
            success "Removed ~/.claude-token"
        else
            info "Kept ~/.claude-token"
        fi
    fi

    echo ""
    printf "${GREEN}${BOLD}"
    echo "  ╭─────────────────────────────────────────────╮"
    echo "  │                                             │"
    echo "  │   ✓  Uninstall complete!                    │"
    echo "  │                                             │"
    echo "  ╰─────────────────────────────────────────────╯"
    printf "${NC}"
    echo ""

    info "Reload your shell: source $shell_config"
    echo ""
}

main "$@"
