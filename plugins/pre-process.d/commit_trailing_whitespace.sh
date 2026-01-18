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
readarray -t staged_files < <(
    "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
)

if [[ ${#staged_files[@]} -eq 0 ]]; then
    return 0
fi

debug "checking ${#staged_files[@]} files for trailing whitespace"

# Get the root of the repo
GIT_ROOT=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

# Array to store files with trailing whitespace
declare -a files_with_whitespace=()

# Check each staged file
echo "checking ${#staged_files[@]} for whitespace"
for staged_file in "${staged_files[@]}"; do
    # Get the absolute path of the file
    abs_path="${GIT_ROOT}/${staged_file}"

    # Skip if file doesn't exist
    if [[ ! -f "${abs_path}" ]]; then
        continue
    fi

    # Check if it's a text file using mime type
    mime_type=$(file --brief --mime-type "${abs_path}")
    debug "checking ${staged_file} (mime: ${mime_type})"

    # Check if it's a text file (includes JSON, Python, CSV, etc.)
    if [[ "${mime_type}" =~ ^text/ ]] || \
       [[ "${mime_type}" == "application/json" ]] || \
       [[ "${mime_type}" == "application/javascript" ]] || \
       [[ "${mime_type}" == "application/x-python" ]] || \
       [[ "${mime_type}" == "application/x-shellscript" ]] || \
       [[ "${mime_type}" == "application/x-ruby" ]] || \
       [[ "${mime_type}" == "application/x-perl" ]] || \
       [[ "${mime_type}" == "application/xml" ]] || \
       [[ "${mime_type}" == "application/x-yaml" ]] || \
       [[ "${mime_type}" =~ ^application/.*\+xml$ ]] || \
       [[ "${mime_type}" =~ ^application/.*\+json$ ]]; then

        # Check for trailing whitespace
        if grep -q '[[:space:]]$' "${abs_path}"; then
            debug "found trailing whitespace in ${staged_file}"
            files_with_whitespace+=("${staged_file}")
        else
            debug "no trailing whitespace in ${staged_file}"
        fi
    fi
done

# If we found files with trailing whitespace, fail and provide fix commands
if [[ ${#files_with_whitespace[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: Found trailing whitespace in the following files:"
    echo ""

    for file in "${files_with_whitespace[@]}"; do
        echo "  - ${file}"
    done

    echo ""
    echo "To fix trailing whitespace, run the following commands:"
    echo ""

    for file in "${files_with_whitespace[@]}"; do
        # Print sed command to remove trailing whitespace
        echo "  sed -i 's/[[:space:]]*$//' '${GIT_ROOT}/${file}'"
    done

    echo ""
    echo "Or fix all at once with:"
    echo ""
    echo "  sed -i 's/[[:space:]]*$//' \\"
    for i in "${!files_with_whitespace[@]}"; do
        if [[ $i -eq $((${#files_with_whitespace[@]} - 1)) ]]; then
            echo "    '${GIT_ROOT}/${files_with_whitespace[$i]}'"
        else
            echo "    '${GIT_ROOT}/${files_with_whitespace[$i]}' \\"
        fi
    done
    echo ""

    return 1
fi

debug "no trailing whitespace found"
return 0
