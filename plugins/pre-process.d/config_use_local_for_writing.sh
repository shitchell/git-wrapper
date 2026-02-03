#!/usr/bin/env bash
#
# Use ~/.gitconfig.local for writing --global options rather than ~/.gitconfig
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true

# Determine if --global is specified, if there are 2+ non-option arguments, and
# if a file was manually specified
if [[ -n "${GIT_CONFIG}" ]]; then
    # A file was manually specified by the GIT_CONFIG environment variable
    return 0
fi

IS_GLOBAL=false
ARG_COUNT=0
for arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    if [[ "${arg}" == "--global" ]]; then
        IS_GLOBAL=true
    elif [[ "${arg}" == "--file" ]]; then
        # exit: a config file to use was manually specified by the --file option
        return 0
    elif [[ "${arg}" == "--get" ]]; then
        # This is a get operation, not set, so do nothing
        return 0
    elif [[ "${arg}" =~ ^- ]]; then
        continue
    else
        let ARG_COUNT++
    fi
done

# If --global is specified and there are 2+ non-option arguments (i.e.: we are
# setting a config value), then use ~/.gitconfig.local for writing
if ${IS_GLOBAL} && [[ ${ARG_COUNT} -ge 2 ]]; then
    echo "Using ~/.gitconfig.local for writing --global options"

    # Loop back through the arguments and replace "--global" with "--file"
    git_args=()
    for arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
        if [[ "${arg}" == "--global" ]]; then
            git_args+=("--file" "${HOME}/.gitconfig.local")
        else
            git_args+=("${arg}")
        fi
    done
    export GIT_SUBCOMMAND_ARGS=("${git_args[@]}")
    unset git_args
fi
