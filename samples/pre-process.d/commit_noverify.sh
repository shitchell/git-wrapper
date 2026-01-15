#!/usr/bin/env bash
#
# Block --no-verify when wrapper.disableNoVerify is true
#
# Prevents bypassing pre-commit hooks. Useful for enforcing code quality
# checks in repos where hooks should not be skipped.
#

__disable_noverify=$(wrapper-option --bool --default=false disableNoVerify)

if ! ${__disable_noverify}; then
    return 0
fi

# Check for --no-verify in args
for __arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${__arg}" == "--no-verify" || "${__arg}" == "-n" ]]; then
        echo "error: --no-verify is disabled in this repository" >&2
        RUN_GIT_CMD=false
        return 1
    fi
done
