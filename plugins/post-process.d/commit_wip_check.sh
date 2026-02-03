#!/usr/bin/env bash
#
# Check for WIP notes after committing
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true
#   {plugin-key}.regex (string): default '(#|//|\*).*(^|[^[:alnum:]_])WIP([^[:alnum:]_]|$)'

# Exit if the commit was unsuccessful
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return ${GIT_EXIT_CODE}

# Get the list of files just committed
readarray -t __committed_files < <(
    "${GIT}" "${GIT_ARGS[@]}" log -1 --name-status --no-renames --format="" \
        | grep -E '^(A|C|M)' \
        | sed -e 's/^\w\t//'
)

# If there are no files, do nothing
if [[ ${#__committed_files[@]} -eq 0 ]]; then
    debug "no added/updated files, skipping WIP check"
    return 0
fi

# Find all instances of "WIP" in those files
__wip_regex=$(plugin-option --default='(#|//|\*).*(^|[^[:alnum:]_])WIP([^[:alnum:]_]|$)' regex)
if [[ -z "${__wip_regex}" ]]; then
    warn "{plugin-key}.regex is empty, skipping WIP check"
    return 0
fi
debug "using regex /${__wip_regex}/ against ${#__committed_files[@]} files"
readarray -t __wips < <(
    "${GIT}" "${GIT_ARGS[@]}" -c color.ui=never grep -E "${__wip_regex}" -- "${__committed_files[@]}" \
        | grep -vE '^(Binary|diff|index) file'
)

# If we found WIPs, then print them with a helpful reminder
if [[ "${#__wips[@]}" -gt 0 ]]; then
    printf "${S_BOLD}${C_YELLOW}%s${S_RESET}\n" \
        "WARNING: Found ${#__wips[@]} WIPs in the code:"
    printf "%s\n" "${__wips[@]}" | sed -e 's/^/  /'
fi
