#!/usr/bin/env bash
#
# Uninstall git-wrapper
#
# Removes:
#   - Wrapper symlink from ~/.local/bin/git (or $GIT_WRAPPER_BIN)
#   - Optionally removes plugin config directory
#   - Removes git config entries
#
# Options:
#   --bin-dir DIR       Look for wrapper in DIR (default: ~/.local/bin)
#   --config-dir DIR    Plugin directory location (default: ~/.git.d)
#   --remove-config     Also remove the config/plugins directory
#   --keep-git-config   Don't remove wrapper.* git config entries
#   --dry-run           Show what would be done without doing it
#   -y, --yes           Don't prompt for confirmation
#   -h, --help          Show this help message
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# XDG defaults
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

# Installation defaults
BIN_DIR="${GIT_WRAPPER_BIN:-${HOME}/.local/bin}"
CONFIG_DIR="${GIT_WRAPPER_CONFIG:-${HOME}/.git.d}"

# Options
REMOVE_CONFIG=false
KEEP_GIT_CONFIG=false
DRY_RUN=false
YES=false

# Colors
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Uninstall git-wrapper.

Options:
    --bin-dir DIR       Look for wrapper in DIR (default: ~/.local/bin)
    --config-dir DIR    Plugin directory location (default: \~/.git.d)
    --remove-config     Also remove the config/plugins directory
    --keep-git-config   Don't remove wrapper.* git config entries
    --dry-run           Show what would be done without doing it
    -y, --yes           Don't prompt for confirmation
    -h, --help          Show this help message

Environment variables:
    GIT_WRAPPER_BIN     Override default bin directory
    GIT_WRAPPER_CONFIG  Override default config directory
    XDG_CONFIG_HOME     XDG config directory (default: ~/.config)
EOF
}

log() {
    echo "${C_GREEN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"
}

log_action() {
    echo "    ${C_RED}$1${C_RESET} $2"
}

warn() {
    echo "${C_YELLOW}Warning:${C_RESET} $*" >&2
}

run() {
    if ${DRY_RUN}; then
        echo "    ${C_YELLOW}[dry-run]${C_RESET} $*"
    else
        "$@"
    fi
}

confirm() {
    if ${YES}; then
        return 0
    fi
    local response
    read -rp "$1 [y/N] " response
    [[ "${response}" =~ ^[Yy] ]]
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        --bin-dir=*)
            BIN_DIR="${1#*=}"
            shift
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --config-dir=*)
            CONFIG_DIR="${1#*=}"
            shift
            ;;
        --remove-config)
            REMOVE_CONFIG=true
            shift
            ;;
        --keep-git-config)
            KEEP_GIT_CONFIG=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            YES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Expand paths
BIN_DIR="${BIN_DIR/#\~/$HOME}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

echo "${C_BOLD}git-wrapper uninstaller${C_RESET}"
echo ""

# Check what exists
WRAPPER_EXISTS=false
CONFIG_EXISTS=false

if [[ -e "${BIN_DIR}/git" ]]; then
    WRAPPER_EXISTS=true
fi

if [[ -d "${CONFIG_DIR}" ]]; then
    CONFIG_EXISTS=true
fi

if ! ${WRAPPER_EXISTS} && ! ${CONFIG_EXISTS}; then
    echo "Nothing to uninstall."
    echo "  Wrapper not found at: ${BIN_DIR}/git"
    echo "  Config not found at: ${CONFIG_DIR}/"
    exit 0
fi

# Show what will be removed
echo "The following will be removed:"
if ${WRAPPER_EXISTS}; then
    echo "    ${C_CYAN}${BIN_DIR}/git${C_RESET}"
fi
if ${REMOVE_CONFIG} && ${CONFIG_EXISTS}; then
    echo "    ${C_CYAN}${CONFIG_DIR}/${C_RESET} (and all plugins)"
fi
if ! ${KEEP_GIT_CONFIG}; then
    echo "    ${C_CYAN}git config --global wrapper.*${C_RESET}"
fi
echo ""

if ! ${DRY_RUN} && ! confirm "Continue?"; then
    echo "Aborted."
    exit 1
fi

# Remove wrapper
if ${WRAPPER_EXISTS}; then
    log "Removing wrapper"
    if [[ -L "${BIN_DIR}/git" ]]; then
        log_action "remove" "${BIN_DIR}/git (symlink)"
        run rm "${BIN_DIR}/git"
    else
        warn "${BIN_DIR}/git is not a symlink, skipping"
        warn "Remove it manually if desired"
    fi
fi

# Remove config directory
if ${REMOVE_CONFIG} && ${CONFIG_EXISTS}; then
    log "Removing config directory"
    log_action "remove" "${CONFIG_DIR}/"
    run rm -rf "${CONFIG_DIR}"
fi

# Remove git config
if ! ${KEEP_GIT_CONFIG}; then
    log "Removing git config"
    # Get all wrapper.* config keys
    if ! ${DRY_RUN}; then
        wrapper_keys=$(git config --global --list 2>/dev/null | grep '^wrapper\.' | cut -d= -f1 || true)
        for key in ${wrapper_keys}; do
            log_action "unset" "${key}"
            git config --global --unset "${key}" 2>/dev/null || true
        done
        if [[ -z "${wrapper_keys}" ]]; then
            echo "    (no wrapper.* config entries found)"
        fi
    else
        echo "    ${C_YELLOW}[dry-run]${C_RESET} git config --global --unset wrapper.*"
    fi
fi

echo ""
log "Uninstall complete!"

if ! ${REMOVE_CONFIG} && ${CONFIG_EXISTS}; then
    echo ""
    echo "Config directory preserved at: ${C_CYAN}${CONFIG_DIR}/${C_RESET}"
    echo "Run with ${C_CYAN}--remove-config${C_RESET} to remove it."
fi
