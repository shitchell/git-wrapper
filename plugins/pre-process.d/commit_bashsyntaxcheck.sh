#!/usr/bin/env bash
#
# For any staged files that end with `.sh` or start with a bash shebang, check
# them with `bash -n` to ensure they have valid syntax.
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true

# Set up a function to check for a bash shebang
__has_shebang() {
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

# Get the list of files staged for commit
readarray -t __committed_files < <(
    "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
)
debug "checking files: ${__committed_files[*]}"

# Get the root of the repo
__git_root=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

# Loop over all staged files
for __committed_file in "${__committed_files[@]}"; do
    # Get the absolute path of the file
    __abs_path="${__git_root}/${__committed_file}"
    debug "${__committed_file} -> ${__abs_path}"

    if [[ -f "${__abs_path}" ]]; then
        __is_bash=false
        if [[ "${__committed_file}" =~ \.sh$ ]]; then
            debug "is bash: ${__committed_file}: .sh extension"
            __is_bash=true
        elif __has_shebang "${__abs_path}"; then
            debug "is bash: ${__committed_file}: shebang"
            __is_bash=true
        else
            debug "not bash: ${__committed_file}"
        fi

        if ${__is_bash}; then
            printf "Checking '%s' for syntax errors ... " "${__committed_file}"
            __syntax_err=$(bash -n "${__abs_path}" 2>&1)
            if [[ -n "${__syntax_err}" ]]; then
                echo "error"
                printf "%s\n" "${C_RED}${__syntax_err}${S_RESET}" >&2
                return ${E_PRE_ERROR}
            else
                echo "done"
            fi
        fi
    fi
done
