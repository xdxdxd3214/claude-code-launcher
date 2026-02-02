#!/usr/bin/env bash
# cc.sh - Claude Code Quick Launcher
# https://github.com/ash3in/claude-code-launcher
#
#
# Sourced by shell config. Do not execute directly.

cc() {
    local token_file="$HOME/.claude-token"
    local token=""


    _cc_red()    { printf '\033[31m%s\033[0m\n' "$1"; }
    _cc_green()  { printf '\033[32m%s\033[0m\n' "$1"; }
    _cc_yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
    _cc_cyan()   { printf '\033[36m%s\033[0m\n' "$1"; }
    _cc_bold()   { printf '\033[1m%s\033[0m\n' "$1"; }

    _cc_validate_jwt() {
        local jwt="$1"
        if [[ "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
            return 0
        fi
        return 1
    }

    _cc_check_expiry() {
        local jwt="$1"
        local payload
        payload=$(echo "$jwt" | cut -d'.' -f2)


        local pad=$((4 - ${#payload} % 4))
        [[ $pad -ne 4 ]] && payload="${payload}$(printf '=%.0s' $(seq 1 $pad))"


        local exp
        exp=$(echo "$payload" | base64 -d 2>/dev/null | grep -o '"exp":[0-9]*' | cut -d':' -f2)

        if [[ -n "$exp" ]]; then
            local now
            now=$(date +%s)
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

    _cc_expiry_days() {
        local jwt="$1"
        local payload
        payload=$(echo "$jwt" | cut -d'.' -f2)
        local pad=$((4 - ${#payload} % 4))
        [[ $pad -ne 4 ]] && payload="${payload}$(printf '=%.0s' $(seq 1 $pad))"
        local exp
        exp=$(echo "$payload" | base64 -d 2>/dev/null | grep -o '"exp":[0-9]*' | cut -d':' -f2)
        if [[ -n "$exp" ]]; then
            local now
            now=$(date +%s)
            local diff=$((exp - now))
            echo $((diff / 86400))
        fi
    }


    if [[ "$1" == "-v" || "$1" == "--version" ]]; then
        echo "claude-code-launcher v1.0.0"
        return 0
    fi

    # Secure token update
    if [[ "$1" == "-t" || "$1" == "--token" ]]; then
        if [[ -n "$2" ]]; then
            _cc_red "✗ SECURITY WARNING: Never pass tokens as arguments!"
            _cc_red "  Tokens in arguments are saved to shell history (~/.zsh_history)"
            _cc_red "  and visible in process list (ps aux)"
            echo ""
            _cc_yellow "Removing command from shell history..."
            # Try to remove from history
            fc -p 2>/dev/null || true
            echo ""
        fi

        _cc_cyan "Enter token securely below (input hidden):"
        printf "Token: "
        read -rs token
        echo ""


        if ! _cc_validate_jwt "$token"; then
            _cc_red "✗ Invalid token format (not a valid JWT)"
            return 1
        fi

        # Atomic file creation to prevent TOCTOU
        local tmpfile
        tmpfile=$(mktemp "${token_file}.XXXXXX") || {
            _cc_red "✗ Failed to create temporary file"
            return 1
        }
        chmod 600 "$tmpfile"
        if ! echo "$token" > "$tmpfile"; then
            rm -f "$tmpfile"
            _cc_red "✗ Failed to write token"
            return 1
        fi
        mv -f "$tmpfile" "$token_file" || {
            rm -f "$tmpfile"
            _cc_red "✗ Failed to store token"
            return 1
        }

        _cc_green "✓ Token stored securely"
        _cc_check_expiry "$token"
        return 0
    fi


    if [[ "$1" == "-s" || "$1" == "--status" ]]; then
        _cc_bold "Claude Code Quick Launcher Status"
        echo ""

        if [[ -f "$token_file" ]]; then
            local perms
            perms=$(stat -f "%Lp" "$token_file" 2>/dev/null || stat -c "%a" "$token_file" 2>/dev/null)

            if [[ "$perms" != "600" ]]; then
                _cc_red "✗ WARNING: Token file has insecure permissions: $perms (should be 600)"
                chmod 600 "$token_file"
                _cc_green "✓ Fixed permissions"
            else
                _cc_green "✓ Token file permissions: $perms (secure)"
            fi

            _cc_check_expiry "$(cat "$token_file")"
        else
            _cc_red "✗ No token stored"
            _cc_cyan "  Run: cc -t"
        fi

        echo ""


        if [[ -n "$ANTHROPIC_BASE_URL" ]]; then
            _cc_green "✓ ANTHROPIC_BASE_URL: $ANTHROPIC_BASE_URL"
        else
            _cc_yellow "⚠️ ANTHROPIC_BASE_URL not set (using default)"
        fi

        if command -v claude &>/dev/null; then
            _cc_green "✓ Claude CLI installed"
        else
            _cc_red "✗ Claude CLI not found"
            _cc_cyan "  Run: npm install -g @anthropic-ai/claude-code"
        fi

        return 0
    fi


    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _cc_bold "cc - Claude Code Quick Launcher"
        echo ""
        echo "A secure launcher for enterprise users with JWT authentication."
        echo ""
        _cc_cyan "Usage:"
        echo "  cc              Launch Claude Code"
        echo "  cc -t, --token  Update token (secure hidden input)"
        echo "  cc -s, --status Check token status, expiry, and config"
        echo "  cc -v, --version Show version"
        echo "  cc -h, --help   Show this help"
        echo ""
        _cc_cyan "Examples:"
        echo "  cc -t           # Store a new token"
        echo "  cc -s           # Check if token is valid"
        echo "  cc              # Launch Claude Code"
        echo ""
        _cc_cyan "Security:"
        echo "  - Token stored in ~/.claude-token (mode 600)"
        echo "  - Token input is hidden and never saved to history"
        echo "  - Token cleared from environment after Claude exits"
        echo ""
        _cc_cyan "More info: https://github.com/ash3in/claude-code-launcher"
        return 0
    fi


    if [[ ! -f "$token_file" ]]; then
        _cc_red "✗ No token found"
        _cc_cyan "  Run: cc -t"
        return 1
    fi

    # Enforce permissions
    local perms
    perms=$(stat -f "%Lp" "$token_file" 2>/dev/null || stat -c "%a" "$token_file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        _cc_yellow "⚠️ Fixing insecure token file permissions..."
        chmod 600 "$token_file"
    fi

    token="$(cat "$token_file")"


    if ! _cc_validate_jwt "$token"; then
        _cc_red "✗ Stored token is invalid"
        _cc_cyan "  Run: cc -t"
        return 1
    fi


    if ! _cc_check_expiry "$token"; then
        _cc_cyan "  Run: cc -t to update your token"
        return 1
    fi


    export ANTHROPIC_AUTH_TOKEN="$token"


    if [[ -n "$CC_DISABLE_PROXY" ]]; then
        unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
    fi

    # Launch Claude Code
    claude "$@"
    local exit_code=$?


    unset ANTHROPIC_AUTH_TOKEN

    return $exit_code
}
