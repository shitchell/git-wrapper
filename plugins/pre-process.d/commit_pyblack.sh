#!/usr/bin/env bash
#
# For any staged files that end with `.py` or start with a python shebang, check
# them with `black` to ensure they are formatted correctly.
#
# Config variables:
# - wrapper.black (str): mode ("off"/"disabled", "warn", "error")
#   (default: warn)

# Ensure `black` is installed
if ! command -v black &>/dev/null; then
    echo "black not installed, skipping" >&2
    return 0
fi

# Check if wrapper.black is set
__black_mode=$(wrapper-option --default="warn" black)
if ! [[ "${__black_mode}" == "warn" || "${__black_mode}" == "error" ]]; then
    echo "skipping black check..."
else
    # Get the list of files just committed
    readarray -t committed_files < <(
        "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
    )
    debug "checking files: ${committed_files[*]}"

    # Get the root of the repo
    GIT_ROOT=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

    # Set up a function to check for a python shebang
    function has-shebang() {
        awk '
        FNR == 1 && /^#!\/([^ ]+bin\/|usr\/bin\/env )python/ {
            found=1
            exit 0
        }
        FNR > 1 {
            exit 1
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "${1:-/dev/stdin}"
    }

    # Loop over all subcommand args and find the python files
    __python_files=()
    for committed_file in "${committed_files[@]}"; do
        # Get the absolute path of the file
        abs_path="${GIT_ROOT}/${committed_file}"
        # Get the relative path of the file
        rel_path=$(realpath --relative-to="${PWD:-.}" "${abs_path}")
        debug "${committed_file} -> ${abs_path}"
        if [[ -f "${abs_path}" ]]; then
            __is_py=false
            if [[ "${committed_file}" =~ ".py"$ ]]; then
                debug "is python: ${committed_file}: .py extension"
                __is_py=true
            elif has-shebang "${abs_path}"; then
                debug "is python: ${committed_file}: shebang"
                __is_py=true
            else
                debug "not python: ${committed_file}"
            fi
            if ${__is_py}; then
                __python_files+=("${abs_path}")
            fi
            # if ${__is_py}; then
            #     # A shell script has been found
            #     printf "Checking '%s' with \`black\` ... " "${rel_path}"
            #     output=$(black --diff -- "${rel_path}" 2>&1)
            #     if [[ ${?} -ne 0 ]]; then
            #         echo "error"
            #         # if ${USE_COLOR}; then
            #         #     start_color="\033[31m"
            #         #     end_color="\033[0m"
            #         # fi
            #         echo -e "${start_color}${output}${end_color}" \
            #             | sed 's/^/    /' >&2
            #         return 1
            #     else
            #         echo "done"
            #     fi
            # fi
        fi
    done

    # Check the python files with `black`
    if [[ ${#__python_files[@]} -gt 0 ]]; then
        # shellcheck disable=SC2086
        printf "Checking %d python files with \`black\` ... " \
            ${#__python_files[@]}
        output=$(black --diff -- "${__python_files[@]}" 2>&1)
        if [[ ${?} -ne 0 ]]; then
            echo "error"
            echo -e "${start_color}${output}${end_color}" \
                | sed 's/^/    /' >&2
            return 1
        else
            echo "done"
        fi
    fi
fi
