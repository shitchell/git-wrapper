#!/usr/bin/env bash
#
# For any staged files that end with `.sh` or start with a bash shebang, check
# them with `bash -n` to ensure they have valid syntax.
#
# Config variables:
# - wrapper.bashSyntaxCheckEnabled (bool): Whether to check shell scripts with
#   `bash -n` (default: true)

# Check if bashSyntaxCheckEnabled is set
__bash_syntax_check_enabled=$(wrapper-option --bool --default=true bashSyntaxCheckEnabled)
if ! ${__bash_syntax_check_enabled}; then
    echo "skipping shell syntax check..."
else
    # Get the list of files just committed
    readarray -t committed_files < <(
        "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
    )
    debug "checking files: ${committed_files[*]}"

    # Get the root of the repo
    GIT_ROOT=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

    # Set up a function to check for a bash shebang
    function has-shebang() {
        awk '
        FNR == 1 && /^#!\/(bin\/|usr\/bin\/env )bash/ {
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

    # Loop over all subcommand args
    for committed_file in "${committed_files[@]}"; do
        # Get the absolute path of the file
        abs_path="${GIT_ROOT}/${committed_file}"
        debug "${committed_file} -> ${abs_path}"
        if [[ -f "${abs_path}" ]]; then
            __is_bash=false
            if [[ "${committed_file}" =~ ".sh"$ ]]; then
                debug "is bash: ${committed_file}: .sh extension"
                __is_bash=true
            elif has-shebang "${abs_path}"; then
                debug "is bash: ${committed_file}: shebang"
                __is_bash=true
            else
                debug "not bash: ${committed_file}"
            fi
            if ${__is_bash}; then
                # A shell script has been found
                printf "Checking '%s' for syntax errors ... " "${committed_file}"
                syntax_err=$(bash -n "${abs_path}" 2>&1)
                if [[ -n "${syntax_err}" ]]; then
                    echo "error"
                    if ${USE_COLOR}; then
                        start_color="\033[31m"
                        end_color="\033[0m"
                    fi
                    echo -e "${start_color}${syntax_err}${end_color}" >&2
                    exit 1
                else
                    echo "done"
                fi
            fi
        fi
    done
fi
