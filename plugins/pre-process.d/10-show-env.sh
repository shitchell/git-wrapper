#!/usr/bin/env bash
#
# Show all ^GIT environment variables if enabled or GIT_SHOW_ENV == true
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default false

__show_env="${GIT_SHOW_ENV}"
if [[ -z "${__show_env}" ]]; then
    __show_env=$(plugin-option --bool --default=false enabled)
fi

if [[ "${__show_env}" == "true" ]]; then
    echo "${S_BOLD}GIT ENV:${S_RESET}"
    env | grep '^GIT' | sed 's/^/  - /'
fi
