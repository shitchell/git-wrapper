#!/usr/bin/env bash
#
# Block --no-verify when strict modes are enabled
#
# This hook prevents bypassing pre-commit hooks when either:
# - wrapper.disableNoVerify is true (general protection)
# - docs.strictReview is true (architecture review protection)
#
# If neither is enabled, --no-verify is allowed.
#

# Check if either strict mode is enabled
__disable_noverify=$(wrapper-option --bool --default=false disableNoVerify)
__strict_review=$(git config --get docs.strictReview 2>/dev/null || echo "false")

if ! ${__disable_noverify} && [[ "${__strict_review}" != "true" ]]; then
    # Neither protection is enabled, allow --no-verify
    return 0
fi

# Check for --no-verify in args
for arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${arg}" == "--no-verify" || "${arg}" == "-n" ]]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────┐"
        echo "│  --no-verify is disabled                                        │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        echo ""
        echo "  If you have issues with hooks, escalate to the human rather"
        echo "  than bypassing them."
        echo ""
        {
            date
            echo "User: ${USER}"
            echo "PWD: ${PWD}"
            echo "Command: git ${GIT_SUBCOMMAND} ${GIT_SUBCOMMAND_ARGS[*]}"
            echo ""
            echo "Environment:"
            declare -p CLAUDECODE CLAUDE_CODE 2>/dev/null || echo "(no claude env)"
            echo ""
            echo "---"
            echo ""
        } >> /tmp/noverify-blocked.log
        return 1
    fi
done
