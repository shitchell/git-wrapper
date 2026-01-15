#!/usr/bin/env bash
#
# Check for WIP notes after committing
#
# Config variables:
# - wipEnabled (bool): Whether to check for WIP notes (default: true)

# Exit if the commit was unsuccessful
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return ${GIT_EXIT_CODE}

__wip_enabled=$(wrapper-option --bool --default=true wipEnabled)
if ! ${__wip_enabled}; then
    echo "skipping WIP check..."
else
    # Get the list of files just committed
    readarray -t committed_files < <(
        git "${GIT_ARGS[@]}" log -1 --name-status --no-renames --format="" \
            | grep -E '^(A|C|M)' \
            | sed -e 's/^\w\t//'
    )

    # If there are no files, do nothing
    if [[ ${#committed_files[@]} -eq 0 ]]; then
        debug "no added/updated files, skipping TODO check"
        return 0
    fi

    # Find all instances of "WIP" in those files
    __wip_regex=$(wrapper-option --default='(#|//|\*).*\bWIP\b' wipRegex)
    debug "using regex /${__wip_regex}/ against ${#committed_files[@]} files"
    readarray -t WIPS < <(
        git -c color.ui=never "${GIT_ARGS[@]}" grep -P "${__wip_regex}" -- "${committed_files[@]}" \
            | grep -vE '^(Binary|diff|index) file'
    )

    # If we found WIPs, then print them with a helpful reminder
    if [[ "${#WIPS[@]}" -gt 0 ]]; then
        printf "\033[1;33m%s\033[0m\n" \
            "WARNING: Found ${#WIPS[@]} WIPs in the code:"
        printf "%s\n" "${WIPS[@]}" | sed -e 's/^/  /'
        printf "\033[1;33m%s\033[0m\n" \
            "Just an FYI before you deliver this :) Thanks."
        return 1
    fi
fi
