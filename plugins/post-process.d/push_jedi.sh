#!/usr/bin/env bash
#
# Print a Jedi blessing after force pushes
#
# Config:
#   wrapper.plugin.push_jedi.enabled (bool): default true

# Only run on successful push
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return 0

# Check for --force or -f in args
for __arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${__arg}" == "--force" || "${__arg}" == "-f" ]]; then
        echo "${S_DIM}May the force be with you${S_RESET}"
        return 0
    fi
done
