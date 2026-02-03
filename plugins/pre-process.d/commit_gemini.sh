#!/usr/bin/env bash
#
# Set commit author to Gemini CLI
#
# When the GEMINI_CLI environment variable is set, automatically set the
# commit author to "Gemini CLI" and disable GPG signing.
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true

if [[ -n "${GEMINI_CLI}" ]]; then
    echo "Setting commit author to Gemini CLI"
    GIT_ARGS+=(-c user.name="Gemini CLI" -c user.email="noreply@google.com")
    GIT_ARGS+=(-c commit.gpgsign=false)
fi
