#!/usr/bin/env bash
#
# Install git-wrapper with XDG Base Directory compliance
#
# Installs:
#   - Wrapper script to ~/.local/bin/git (or $GIT_WRAPPER_BIN)
#   - Plugin directories to ~/.git.d/ (or $GIT_WRAPPER_CONFIG)
#
# Options:
#   --bin-dir DIR       Install wrapper to DIR (default: ~/.local/bin)
#   --config-dir DIR    Install plugins to DIR (default: ~/.git.d)
#   --with-plugins      Copy sample plugins to config directory
#   --no-config         Skip setting git config for scriptDir
#   --dry-run           Show what would be done without doing it
#   --uninstall         Remove installation (same as running uninstall.sh)
#   -h, --help          Show this help message
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# XDG defaults
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

# Installation defaults
BIN_DIR="${GIT_WRAPPER_BIN:-${HOME}/.local/bin}"
CONFIG_DIR="${GIT_WRAPPER_CONFIG:-${HOME}/.git.d}"

# Options
WITH_PLUGINS=false
SET_CONFIG=true
DRY_RUN=false

# Colors
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install git-wrapper with XDG Base Directory compliance.

Options:
    --bin-dir DIR       Install wrapper to DIR (default: ~/.local/bin)
    --config-dir DIR    Install plugins to DIR (default: \~/.git.d)
    --with-plugins      Copy sample plugins to config directory
    --no-config         Skip setting git config for scriptDir
    --dry-run           Show what would be done without doing it
    --uninstall         Remove installation (same as running uninstall.sh)
    -h, --help          Show this help message

Environment variables:
    GIT_WRAPPER_BIN     Override default bin directory
    GIT_WRAPPER_CONFIG  Override default config directory
    XDG_CONFIG_HOME     XDG config directory (default: ~/.config)

Examples:
    $(basename "$0")                      # Standard install
    $(basename "$0") --with-plugins       # Install with sample plugins
    $(basename "$0") --dry-run            # Preview installation
EOF
}

log() {
    echo "${C_GREEN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"
}

log_action() {
    echo "    ${C_CYAN}$1${C_RESET} $2"
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
        --with-plugins)
            WITH_PLUGINS=true
            shift
            ;;
        --no-config)
            SET_CONFIG=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            exec "${SCRIPT_DIR}/uninstall.sh" "$@"
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

echo "${C_BOLD}git-wrapper installer${C_RESET}"
echo ""

# Check if wrapper already exists
if [[ -e "${BIN_DIR}/git" ]]; then
    if [[ -L "${BIN_DIR}/git" ]]; then
        existing_target=$(readlink -f "${BIN_DIR}/git")
        if [[ "${existing_target}" == "${SCRIPT_DIR}/bin/git" ]]; then
            log "Wrapper already installed at ${BIN_DIR}/git"
        else
            warn "Existing symlink at ${BIN_DIR}/git points to: ${existing_target}"
            warn "Remove it first or use a different --bin-dir"
            exit 1
        fi
    else
        warn "File already exists at ${BIN_DIR}/git (not a symlink)"
        warn "Remove it first or use a different --bin-dir"
        exit 1
    fi
else
    # Install wrapper
    log "Installing wrapper"
    log_action "create" "${BIN_DIR}/"
    run mkdir -p "${BIN_DIR}"
    log_action "symlink" "${BIN_DIR}/git -> ${SCRIPT_DIR}/bin/git"
    run ln -sf "${SCRIPT_DIR}/bin/git" "${BIN_DIR}/git"
fi

# Create config directory structure
log "Setting up config directory"
log_action "create" "${CONFIG_DIR}/pre-process.d/"
run mkdir -p "${CONFIG_DIR}/pre-process.d"
log_action "create" "${CONFIG_DIR}/post-process.d/"
run mkdir -p "${CONFIG_DIR}/post-process.d"

# Copy plugins if requested
if ${WITH_PLUGINS}; then
    log "Installing sample plugins"
    for plugin in "${SCRIPT_DIR}/plugins/pre-process.d/"*.sh; do
        [[ -f "${plugin}" ]] || continue
        plugin_name=$(basename "${plugin}")
        log_action "copy" "pre-process.d/${plugin_name}"
        run cp "${plugin}" "${CONFIG_DIR}/pre-process.d/"
        run chmod +x "${CONFIG_DIR}/pre-process.d/${plugin_name}"
    done
    for plugin in "${SCRIPT_DIR}/plugins/post-process.d/"*.sh; do
        [[ -f "${plugin}" ]] || continue
        plugin_name=$(basename "${plugin}")
        log_action "copy" "post-process.d/${plugin_name}"
        run cp "${plugin}" "${CONFIG_DIR}/post-process.d/"
        run chmod +x "${CONFIG_DIR}/post-process.d/${plugin_name}"
    done
fi

# Set git config
if ${SET_CONFIG}; then
    log "Configuring git"
    log_action "config" "wrapper.scriptDir = ${CONFIG_DIR}"
    if ! ${DRY_RUN}; then
        git config --global wrapper.scriptDir "${CONFIG_DIR}"
    else
        echo "    ${C_YELLOW}[dry-run]${C_RESET} git config --global wrapper.scriptDir '${CONFIG_DIR}'"
    fi
fi

echo ""
log "Installation complete!"
echo ""
echo "Make sure ${C_CYAN}${BIN_DIR}${C_RESET} is in your PATH (before /usr/bin)."
echo ""
echo "To add plugins, place executable scripts in:"
echo "    ${C_CYAN}${CONFIG_DIR}/pre-process.d/${C_RESET}   (run before git commands)"
echo "    ${C_CYAN}${CONFIG_DIR}/post-process.d/${C_RESET}  (run after git commands)"
echo ""
if ! ${WITH_PLUGINS}; then
    echo "Run with ${C_CYAN}--with-plugins${C_RESET} to install sample plugins."
    echo ""
fi
