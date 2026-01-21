#!/usr/bin/env bash
#
# Warn or block --no-verify usage
#
# Config:
#   wrapper.plugin.commit_noverify.enabled (bool): default true
#   wrapper.plugin.commit_noverify.mode (string): "warn" or "strict" (default: warn)
#     - warn: print warning but allow commit
#     - strict: block the commit

__mode=$(plugin-option --default=warn mode)

# Check for --no-verify in args
for __arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${__arg}" == "--no-verify" || "${__arg}" == "-n" ]]; then
        if [[ "${__mode}" == "strict" ]]; then
            echo ""
            echo " ┌─────────────────────────────────────────────────────────────────┐"
            echo " │  --no-verify is disabled                                        │"
            echo " └─────────────────────────────────────────────────────────────────┘"
            echo ""
            echo " If you take issue with a git hook, escalate to a human rather"
            echo " than bypassing it."
            echo ""
            __action="BLOCKED"
            __exit_code=${E_PRE_ERROR}
        else
            echo ""
            echo "${S_DIM}Warning: you have bypassed commit hooks. You should report this"
            echo "action for review and discussion why the hook warranted bypassing."
            echo "Otherwise, you should consider resetting your commit and retrying in"
            echo "accordance with the established procedures of this repository.${S_RESET}"
            echo ""
            __action="WARNING"
            __exit_code=0
        fi

        # Log the --no-verify usage
        __log_dir="${HOME}/.cache/git-wrapper"
        __log_file="${__log_dir}/noverify.log"
        if [[ ! -d "${__log_dir}" ]]; then
            mkdir -p "${__log_dir}"
            chmod 700 "${__log_dir}"
        fi
        {
            date
            echo "Action: ${__action}"
            echo "User: ${USER}"
            echo "PWD: ${PWD}"
            echo "Command: git ${GIT_SUBCOMMAND} ${GIT_SUBCOMMAND_ARGS[*]}"
            echo ""
            echo "Environment:"
            declare -p CLAUDECODE CLAUDE_CODE 2>/dev/null || echo "(no claude env)"
            echo ""
            echo "---"
            echo ""
        } >> "${__log_file}"
        chmod 600 "${__log_file}" 2>/dev/null

        return ${__exit_code}
    fi
done
