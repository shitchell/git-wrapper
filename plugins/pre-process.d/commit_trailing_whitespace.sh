#!/usr/bin/env bash
#
# Check all staged text files for trailing whitespace using the `file` command
# to detect mime types. If any files have trailing whitespace, print sed
# commands to fix them and fail the commit.
#
# Config:
#   wrapper.plugin.commit_trailing_whitespace.enabled (bool): default true

debug "running whitespace check"

# Ensure `file` command is installed
if ! command -v file &>/dev/null; then
    echo "file command not installed, skipping trailing whitespace check" >&2
    return 0
fi

# Get the list of staged files
readarray -t __staged_files < <(
    "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
)

if [[ ${#__staged_files[@]} -eq 0 ]]; then
    return 0
fi

debug "checking ${#__staged_files[@]} files for trailing whitespace"

# Get the root of the repo
__git_root=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

# Array to store files with trailing whitespace
declare -a __files_with_whitespace=()

# Check each staged file
for __staged_file in "${__staged_files[@]}"; do
    # Get the absolute path of the file
    __abs_path="${__git_root}/${__staged_file}"

    # Skip if file doesn't exist
    if [[ ! -f "${__abs_path}" ]]; then
        continue
    fi

    # Check if it's a text file using mime type
    __mime_type=$(file --brief --mime-type "${__abs_path}")
    debug "checking ${__staged_file} (mime: ${__mime_type})"

    # Check if it's a text file (includes JSON, Python, CSV, etc.)
    if [[ "${__mime_type}" =~ ^text/ ]] || \
       [[ "${__mime_type}" == "application/json" ]] || \
       [[ "${__mime_type}" == "application/javascript" ]] || \
       [[ "${__mime_type}" == "application/x-python" ]] || \
       [[ "${__mime_type}" == "application/x-shellscript" ]] || \
       [[ "${__mime_type}" == "application/x-ruby" ]] || \
       [[ "${__mime_type}" == "application/x-perl" ]] || \
       [[ "${__mime_type}" == "application/xml" ]] || \
       [[ "${__mime_type}" == "application/x-yaml" ]] || \
       [[ "${__mime_type}" =~ ^application/.*\+xml$ ]] || \
       [[ "${__mime_type}" =~ ^application/.*\+json$ ]]; then

        # Check for trailing whitespace
        if grep -q '[[:space:]]$' "${__abs_path}"; then
            debug "found trailing whitespace in ${__staged_file}"
            __files_with_whitespace+=("${__staged_file}")
        else
            debug "no trailing whitespace in ${__staged_file}"
        fi
    fi
done

# If we found files with trailing whitespace, fail and provide fix commands
if [[ ${#__files_with_whitespace[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: Found trailing whitespace in the following files:"
    echo ""

    for __file in "${__files_with_whitespace[@]}"; do
        echo "  - ${__file}"
    done

    echo ""
    echo "To fix trailing whitespace, run the following commands:"
    echo ""

    for __file in "${__files_with_whitespace[@]}"; do
        # Print sed command to remove trailing whitespace
        echo "  sed -i 's/[[:space:]]*$//' '${__git_root}/${__file}'"
    done

    echo ""
    echo "Or fix all at once with:"
    echo ""
    echo "  sed -i 's/[[:space:]]*$//' \\"
    for __i in "${!__files_with_whitespace[@]}"; do
        if [[ ${__i} -eq $((${#__files_with_whitespace[@]} - 1)) ]]; then
            echo "    '${__git_root}/${__files_with_whitespace[${__i}]}'"
        else
            echo "    '${__git_root}/${__files_with_whitespace[${__i}]}' \\"
        fi
    done
    echo ""

    return 1
fi

debug "no trailing whitespace found"
return 0
