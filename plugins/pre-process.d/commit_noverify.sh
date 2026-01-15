#!/usr/bin/env bash
#
# Block --no-verify when strict mode is enabled.
#
# Prevents bypassing pre-commit hooks. Useful for enforcing code quality
# checks in repos where hooks should not be skipped.
#
# Config:
#   wrapper.plugin.commit_noverify.enabled (bool): default true
#   wrapper.plugin.commit_noverify.strict (bool): default false
#

__strict=$(plugin-option --bool --default=false strict)

if ! ${__strict}; then
    return 0
fi

# Check for --no-verify in args
for __arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${__arg}" == "--no-verify" || "${__arg}" == "-n" ]]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────┐"
        echo "│  --no-verify is disabled                                        │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        echo ""
        RUN_GIT_CMD=false
        return 1
    fi
done
