#!/usr/bin/env bash
#
# Check for TODO notes after committing
#
# Config:
#   wrapper.plugin.commit_todo_check.enabled (bool): default true
#   wrapper.plugin.commit_todo_check.regex (string): default '(^|[^[:alnum:]_])TODO:'

# Exit if the commit was unsuccessful
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return ${GIT_EXIT_CODE}

# Get the list of files just committed, excluding deleted files
readarray -t __committed_files < <(
    "${GIT}" "${GIT_ARGS[@]}" log -1 --name-status --no-renames --format="" \
        | grep -E '^(A|C|M)' \
        | sed -e 's/^\w\t//'
)

# If there are no files, do nothing
if [[ ${#__committed_files[@]} -eq 0 ]]; then
    debug "no added/updated files, skipping TODO check"
    return 0
fi

# Find all instances of "TODO:" in those files, excluding binary files
__todo_regex=$(plugin-option --default='(^|[^[:alnum:]_])TODO:' regex)
if [[ -z "${__todo_regex}" ]]; then
    warn "wrapper.plugin.commit_todo_check.regex is empty, skipping TODO check"
    return 0
fi
debug "using regex /${__todo_regex}/ against ${#__committed_files[@]} files"
readarray -t __todos < <(
    "${GIT}" "${GIT_ARGS[@]}" -c color.ui=never grep -E "${__todo_regex}" -- "${__committed_files[@]}" \
        | grep -vE '^(Binary|diff|index) file'
)

# If we found "TODO:"s, then print them with a helpful reminder
if [[ "${#__todos[@]}" -gt 0 ]]; then
    printf "${S_BOLD}${C_YELLOW}%s${S_RESET}\n" \
        "WARNING: Found ${#__todos[@]} TODOs in the code:"
    printf "%s\n" "${__todos[@]}" | sed -e 's/^/  /'
fi
