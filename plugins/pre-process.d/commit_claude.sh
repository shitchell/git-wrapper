#!/usr/bin/env bash
#
# Configure GPG signing and set author when running inside Claude Code
#
# When the CLAUDECODE environment variable is set, automatically set the author
# to "Claude Code". If a GPG key exists for "Claude Code <noreply@anthropic.com>",
# enable signing with that key; otherwise, disable GPG signing.
#
# Config:
#   wrapper.plugin.commit_claude.enabled (bool): default true

if [[ -n "${CLAUDECODE}" ]]; then
    GIT_ARGS+=(-c user.name="Claude Code" -c user.email="noreply@anthropic.com")

    # Check if gpg is available
    if ! command -v gpg &>/dev/null; then
        debug "gpg not installed, disabling signing"
        GIT_ARGS+=(-c commit.gpgsign=false)
        return 0
    fi

    # Check if a GPG key exists for Claude Code
    claude_key_id=$(gpg --list-secret-keys --keyid-format=long "Claude Code <noreply@anthropic.com>" 2>/dev/null \
        | grep -E "^sec" | head -1 | sed 's/.*\/\([A-Fa-f0-9]*\) .*/\1/')

    if [[ -n "${claude_key_id}" ]]; then
        echo "Enabling GPG signing for Claude Code session (key: ${claude_key_id})"
        GIT_ARGS+=(-c commit.gpgsign=true -c user.signingkey="${claude_key_id}")
    else
        echo "No GPG key found for Claude Code, disabling signing"
        GIT_ARGS+=(-c commit.gpgsign=false)
    fi
fi
