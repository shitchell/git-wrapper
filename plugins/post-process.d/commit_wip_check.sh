#!/usr/bin/env bash
#
# Check for WIP notes after committing
#
# Config:
#   wrapper.plugin.commit_wip_check.enabled (bool): default true
#   wrapper.plugin.commit_wip_check.regex (string): default '(#|//|\*).*\bWIP\b'

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
__wip_regex=$(plugin-option --default='(#|//|\*).*\bWIP\b' regex)
debug "using regex /${__wip_regex}/ against ${#__committed_files[@]} files"
readarray -t __wips < <(
    "${GIT}" "${GIT_ARGS[@]}" -c color.ui=never grep -E "${__wip_regex}" -- "${__committed_files[@]}" \
        | grep -vE '^(Binary|diff|index) file'
)

# If we found WIPs, then print them with a helpful reminder
if [[ "${#__wips[@]}" -gt 0 ]]; then
    printf "\033[1;33m%s\033[0m\n" \
        "WARNING: Found ${#__wips[@]} WIPs in the code:"
    printf "%s\n" "${__wips[@]}" | sed -e 's/^/  /'
    printf "\033[1;33m%s\033[0m\n" \
        "Just an FYI before you deliver this :) Thanks."
    return ${E_POST_ERROR}
fi
