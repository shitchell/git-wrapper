#!/usr/bin/env bash
#
# Check for TODO notes after committing
#
# Config variables:
# - todoEnabled (bool): Whether to check for TODOs (default: true)

# Exit if the commit was unsuccessful
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return ${GIT_EXIT_CODE}

# Check if todoEnabled is set
__todo_enabled=$(wrapper-option --bool --default=true todoEnabled)
if ! ${__todo_enabled}; then
    echo "skipping TODO check..."
else
    # Get the list of files just committed, excluding deleted files
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

    # Find all instances of "TODO:" in those files, excluding binary files
    __todo_regex=$(wrapper-option --default='\bTODO:' todoRegex)
    debug "using regex /${__todo_regex}/ against ${#committed_files[@]} files"
    readarray -t TODOS < <(
        git -c color.ui=never "${GIT_ARGS[@]}" grep "${__todo_regex}" -- "${committed_files[@]}" \
            | grep -vE '^(Binary|diff|index) file'
    )

    # If we found "TODO:"s, then print them with a helpful reminder
    if [[ "${#TODOS[@]}" -gt 0 ]]; then
        printf "\033[1;33m%s\033[0m\n" \
            "WARNING: Found ${#TODOS[@]} TODOs in the code:"
        printf "%s\n" "${TODOS[@]}" | sed -e 's/^/  /'
        printf "\033[1;33m%s\033[0m\n" \
            "Please actually get around to these at some point. Thanks."
        return 0
    fi
fi
