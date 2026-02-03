#!/usr/bin/env bash
#
# Test stuff
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true

if [[ "${GIT_TEST}" == "true" ]]; then
    echo "this is a stdout test"
    echo "this is a stderr test" >&2
    echo "this is another stderr test" >&2
    echo "this is another stdout test"
    GIT_SUBCOMMAND_ARGS+=( --verbose )
fi

if [[ -n "${GIT_FAIL}" ]]; then
    [[ "${GIT_FAIL}" =~ ^[0-9]+$ ]] && return ${GIT_FAIL}
    return 1
fi
