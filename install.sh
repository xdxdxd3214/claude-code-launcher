#!/usr/bin/env bash
#
# claude-code-launcher installer
# https://github.com/ash3in/claude-code-launcher
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/ash3in/claude-code-launcher/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/ash3in/claude-code-launcher.git
#   cd claude-code-launcher && ./install.sh
#

set -e

VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/ash3in/claude-code-launcher/main"



RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m' # Fallback for brown/orange
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Try to use 256 colors for better Claude Orange if supported
if [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]; then
    ORANGE='\033[38;5;208m'
fi

print_banner() {
    echo ""
    printf "${ORANGE}${BOLD}"
    echo "  ╭─────────────────────────────────────────────╮"
    echo "  │                                             │"
    echo "  │   ✴  Claude Code Quick Launcher             │"
    echo "  │                                             │"
    echo "  ╰─────────────────────────────────────────────╯"
    printf "${NC}"
    echo ""
    printf "${DIM}  v${VERSION}${NC}\n"
    echo ""
}

info()    { printf "${CYAN}ℹ ${NC}%s\n" "$1"; }
success() { printf "${GREEN}✓ ${NC}%s\n" "$1"; }
warn()    { printf "${YELLOW}⚠️ ${NC}%s\n" "$1"; }
error()   { printf "${RED}✗ ${NC}%s\n" "$1"; }
prompt()  { printf "${ORANGE}▶ ${NC}${BOLD}%s${NC} " "$1"; }

sanitize_for_shell() {
    local input="$1"
    # Replace ' with '\'' (end quote, escaped quote, start quote)
    printf '%s' "${input//\'/\'\\\'\'}"
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

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.cc-backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        echo "$backup"
    fi
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

    prompt "$question $hint"
    read -r response < /dev/tty
    response="${response:-$default}"

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

ask_input() {
    local question="$1"
    local default="$2"
    local hint=""

    [[ -n "$default" ]] && hint="${DIM}($default)${NC} "

    prompt "$question"
    printf "%s" "$hint"
    read -r response < /dev/tty
    echo "${response:-$default}"
}



check_prerequisites() {
    local has_errors=0

    echo ""
    printf "${BOLD}Checking prerequisites...${NC}\n"
    echo ""


    local shell_type
    shell_type=$(detect_shell)
    if [[ "$shell_type" == "unknown" ]]; then
        warn "Unknown shell. Will try to install anyway."
    else
        success "Shell: $shell_type"
    fi


    if command -v claude &>/dev/null; then
        success "Claude CLI installed"
    else
        warn "Claude CLI not found"
        info "Install with: npm install -g @anthropic-ai/claude-code"
        has_errors=1
    fi


    if command -v curl &>/dev/null; then
        success "curl available"
    else
        warn "curl not found"
    fi

    echo ""
    return $has_errors
}



run_wizard() {
    local config_vars=()

    echo ""
    printf "${BOLD}Configuration${NC}\n"
    printf "${DIM}Press Enter to skip optional fields${NC}\n"
    echo ""


    prompt "ANTHROPIC_BASE_URL (your corporate endpoint):"
    echo ""
    printf "  ${DIM}Example: https://anthropic.internal.company.com${NC}\n"
    printf "  "
    read -r base_url < /dev/tty
    if [[ -n "$base_url" ]]; then
        local safe_base_url
        safe_base_url=$(sanitize_for_shell "$base_url")
        config_vars+=("export ANTHROPIC_BASE_URL='$safe_base_url'")
        ANTHROPIC_BASE_URL="$base_url"
    fi

    echo ""


    if ask_yes_no "Need custom CA certificate?" "n"; then
        prompt "Path to CA cert file:"
        echo ""
        printf "  ${DIM}Example: ~/certs/ca.pem${NC}\n"
        printf "  "
        read -r ca_cert < /dev/tty
        if [[ -n "$ca_cert" ]]; then
            # Expand ~ to $HOME
            ca_cert="${ca_cert/#\~/$HOME}"
            local safe_ca_cert
            safe_ca_cert=$(sanitize_for_shell "$ca_cert")
            config_vars+=("export NODE_EXTRA_CA_CERTS='$safe_ca_cert'")
            if [[ -n "$base_url" ]]; then
                config_vars+=("export AWS_CA_BUNDLE='$safe_ca_cert'")
            fi
        fi
    fi

    echo ""


    if ask_yes_no "Disable proxy for Claude endpoint?" "n"; then
        config_vars+=("export CC_DISABLE_PROXY=1")
        if [[ -n "$ANTHROPIC_BASE_URL" ]]; then
            # Extract hostname from URL
            local hostname
            hostname=$(echo "$ANTHROPIC_BASE_URL" | sed -E 's|https?://([^/]+).*|\1|')
            local safe_hostname
            safe_hostname=$(sanitize_for_shell "$hostname")
            config_vars+=("export NO_PROXY='$safe_hostname,localhost,127.0.0.1'")
            config_vars+=("export no_proxy='$safe_hostname,localhost,127.0.0.1'")
        fi
    fi

    echo ""


    CONFIG_VARS=("${config_vars[@]}")
}



install_cc_function() {
    local shell_config="$1"

    echo ""
    printf "${BOLD}Installing claude-code-launcher...${NC}\n"
    echo ""

    # Backup
    local backup
    backup=$(backup_file "$shell_config")
    if [[ -n "$backup" ]]; then
        success "Backed up $shell_config to $backup"
    fi

    # Check if already installed
    if grep -q "claude-code-launcher START" "$shell_config" 2>/dev/null; then
        warn "claude-code-launcher already installed in $shell_config"
        if ask_yes_no "Reinstall?" "y"; then
            # Remove existing installation
            sed -i.tmp '/# claude-code-launcher START/,/# claude-code-launcher END/d' "$shell_config"
            rm -f "${shell_config}.tmp"
            success "Removed existing installation"
        else
            return 1
        fi
    fi


    local config_block=""
    config_block+=$'\n'
    config_block+="# claude-code-launcher START - https://github.com/ash3in/claude-code-launcher"$'\n'
    config_block+="# Installed: $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    config_block+=$'\n'


    for var in "${CONFIG_VARS[@]}"; do
        config_block+="$var"$'\n'
    done

    if [[ ${#CONFIG_VARS[@]} -gt 0 ]]; then
        config_block+=$'\n'
    fi


    config_block+='# Claude Code quick launcher
cc() {
    local token_file="$HOME/.claude-token"
    local token=""

    _cc_red()    { printf '\''\033[31m%s\033[0m\n'\'' "$1"; }
    _cc_green()  { printf '\''\033[32m%s\033[0m\n'\'' "$1"; }
    _cc_yellow() { printf '\''\033[33m%s\033[0m\n'\'' "$1"; }
    _cc_cyan()   { printf '\''\033[36m%s\033[0m\n'\'' "$1"; }
    _cc_bold()   { printf '\''\033[1m%s\033[0m\n'\'' "$1"; }
    _cc_orange() { 
        if [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]; then
             printf '\''\033[38;5;208m%s\033[0m\n'\'' "$1"
        else
             printf '\''\033[33m%s\033[0m\n'\'' "$1"
        fi
    }

    _cc_validate_jwt() {
        local jwt="$1"
        [[ "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
    }

    _cc_check_expiry() {
        local jwt="$1"
        local payload=$(echo "$jwt" | cut -d'\''\.'\'' -f2)
        local pad=$((4 - ${#payload} % 4))
        [[ $pad -ne 4 ]] && payload="${payload}$(printf '\''=%.0s'\'' $(seq 1 $pad))"
        local exp=$(echo "$payload" | base64 -d 2>/dev/null | grep -o '\''"exp":[0-9]*'\'' | cut -d'\'':'\'' -f2)
        if [[ -n "$exp" ]]; then
            local now=$(date +%s)
            local diff=$((exp - now))
            if [[ $diff -lt 0 ]]; then
                _cc_red "✗ Token EXPIRED $((-diff / 86400)) days ago"
                return 1
            elif [[ $diff -lt 86400 ]]; then
                _cc_yellow "⚠️ Token expires in $((diff / 3600)) hours"
            else
                _cc_green "✓ Token valid for $((diff / 86400)) days"
            fi
        fi
        return 0
    }

    if [[ "$1" == "-v" || "$1" == "--version" ]]; then
        echo "claude-code-launcher v1.0.0"
        return 0
    fi

    if [[ "$1" == "-t" || "$1" == "--token" ]]; then
        [[ -n "$2" ]] && {
            _cc_red "✗ SECURITY WARNING: Never pass tokens as arguments!"
            _cc_red "  Tokens in arguments are saved to shell history (~/.zsh_history)"
            _cc_red "  and visible in process list (ps aux)"
            echo ""
            _cc_yellow "Removing command from shell history..."
            # Try to remove from history
            fc -p 2>/dev/null || true
            echo ""
        }
        _cc_orange "Enter token securely below (input hidden):"
        printf "Token: "; read -rs token; echo ""
        if ! _cc_validate_jwt "$token"; then
            _cc_red "✗ Invalid token format (not a valid JWT)"
            return 1
        fi
        local tmpfile; tmpfile=$(mktemp "${token_file}.XXXXXX") || { _cc_red "✗ Failed to create temp file"; return 1; }
        chmod 600 "$tmpfile"
        if ! echo "$token" > "$tmpfile"; then rm -f "$tmpfile"; _cc_red "✗ Failed to write token"; return 1; fi
        mv -f "$tmpfile" "$token_file" || { rm -f "$tmpfile"; _cc_red "✗ Failed to store token"; return 1; }
        _cc_green "✓ Token stored securely"
        _cc_check_expiry "$token"
        return 0
    fi

    if [[ "$1" == "-s" || "$1" == "--status" ]]; then
        _cc_orange "Claude Code Quick Launcher Status"; echo ""
        if [[ -f "$token_file" ]]; then
            local perms=$(stat -f "%Lp" "$token_file" 2>/dev/null || stat -c "%a" "$token_file" 2>/dev/null)
            [[ "$perms" != "600" ]] && { _cc_red "✗ Insecure permissions: $perms"; chmod 600 "$token_file"; _cc_green "✓ Fixed"; } || _cc_green "✓ Permissions: $perms"
            _cc_check_expiry "$(cat "$token_file")"
        else
            _cc_red "✗ No token stored"
            _cc_orange "  Run: cc -t"
        fi
        echo ""
        [[ -n "$ANTHROPIC_BASE_URL" ]] && _cc_green "✓ Endpoint: $ANTHROPIC_BASE_URL" || _cc_yellow "⚠️ Using default endpoint"
        command -v claude &>/dev/null && _cc_green "✓ Claude CLI installed" || { _cc_red "✗ Claude CLI not found"; _cc_orange "  Run: npm install -g @anthropic-ai/claude-code"; }
        return 0
    fi

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _cc_orange "cc - Claude Code Quick Launcher"; echo ""
        echo "Usage:"
        echo "  cc              Launch Claude Code"
        echo "  cc -t, --token  Update token (secure input)"
        echo "  cc -s, --status Check status and expiry"
        echo "  cc -h, --help   Show this help"
        return 0
    fi

    [[ ! -f "$token_file" ]] && { _cc_red "✗ No token found"; _cc_orange "  Run: cc -t"; return 1; }
    local perms=$(stat -f "%Lp" "$token_file" 2>/dev/null || stat -c "%a" "$token_file" 2>/dev/null)
    [[ "$perms" != "600" ]] && { _cc_yellow "⚠️ Fixing permissions..."; chmod 600 "$token_file"; }
    token="$(cat "$token_file")"
    _cc_validate_jwt "$token" || { _cc_red "✗ Invalid stored token"; _cc_orange "  Run: cc -t"; return 1; }
    _cc_check_expiry "$token" || { _cc_orange "  Run: cc -t to update your token"; return 1; }

    export ANTHROPIC_AUTH_TOKEN="$token"
    [[ -n "$CC_DISABLE_PROXY" ]] && unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
    claude "$@"
    local rc=$?
    unset ANTHROPIC_AUTH_TOKEN
    return $rc
}
'

    config_block+=$'\n'
    config_block+="# claude-code-launcher END"$'\n'


    echo "$config_block" >> "$shell_config"

    success "Installed cc function to $shell_config"
}



main() {
    print_banner


    check_prerequisites || true


    local shell_type
    shell_type=$(detect_shell)
    local shell_config
    shell_config=$(get_shell_config "$shell_type")

    info "Shell config: $shell_config"


    run_wizard


    install_cc_function "$shell_config" || exit 1


    echo ""
    printf "${GREEN}${BOLD}"
    echo "  ╭─────────────────────────────────────────────╮"
    echo "  │                                             │"
    echo "  │   ✓  Installation complete!                 │"
    echo "  │                                             │"
    echo "  ╰─────────────────────────────────────────────╯"
    printf "${NC}"
    echo ""

    printf "${CYAN}Next steps:${NC}\n"
    echo ""
    echo "  1. Reload your shell:"
    printf "     ${BOLD}source $shell_config${NC}\n"
    echo ""
    echo "  2. Store your JWT token:"
    printf "     ${BOLD}cc -t${NC}\n"
    echo ""
    echo "  3. Launch Claude Code:"
    printf "     ${BOLD}cc${NC}\n"
    echo ""

    printf "${DIM}For help: cc -h${NC}\n"
    printf "${DIM}Uninstall: curl -sSL $REPO_URL/uninstall.sh | bash${NC}\n"
    echo ""
}

main "$@"
