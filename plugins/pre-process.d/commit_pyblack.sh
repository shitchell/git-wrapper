#!/usr/bin/env bash
#
# For any staged files that end with `.py` or start with a python shebang, check
# them with `black` to ensure they are formatted correctly.
#
# Config:
#   wrapper.plugin.commit_pyblack.enabled (bool): default true
#   wrapper.plugin.commit_pyblack.mode (str): "warn" or "error" (default: warn)

# Ensure `black` is installed
if ! command -v black &>/dev/null; then
    echo "black not installed, skipping" >&2
    return 0
fi

# Check mode (default: warn)
__black_mode=$(plugin-option --default="warn" mode)
if [[ "${__black_mode}" != "warn" && "${__black_mode}" != "error" ]]; then
    return 0
fi

# Set up a function to check for a python shebang
__has_shebang() {
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

# Get the list of files staged for commit
readarray -t __committed_files < <(
    "${GIT}" "${GIT_ARGS[@]}" diff --staged --name-only --diff-filter=ACMR
)
debug "checking files: ${__committed_files[*]}"

# Get the root of the repo
__git_root=$("${GIT}" "${GIT_ARGS[@]}" rev-parse --show-toplevel)

# Loop over all staged files and find the python files
__python_files=()
for __committed_file in "${__committed_files[@]}"; do
    __abs_path="${__git_root}/${__committed_file}"
    debug "${__committed_file} -> ${__abs_path}"

    if [[ -f "${__abs_path}" ]]; then
        __is_py=false
        if [[ "${__committed_file}" =~ \.py$ ]]; then
            debug "is python: ${__committed_file}: .py extension"
            __is_py=true
        elif __has_shebang "${__abs_path}"; then
            debug "is python: ${__committed_file}: shebang"
            __is_py=true
        else
            debug "not python: ${__committed_file}"
        fi

        if ${__is_py}; then
            __python_files+=("${__abs_path}")
        fi
    fi
done

# Check the python files with `black`
if [[ ${#__python_files[@]} -gt 0 ]]; then
    printf "Checking %d python files with \`black\` ... " "${#__python_files[@]}"
    __output=$(black --check --diff -- "${__python_files[@]}" 2>&1)
    __exit_code=$?

    if [[ ${__exit_code} -ne 0 ]]; then
        echo "error"
        if ${USE_COLOR}; then
            __start_color="\033[31m"
            __end_color="\033[0m"
        else
            __start_color=""
            __end_color=""
        fi
        echo -e "${__start_color}${__output}${__end_color}" | sed 's/^/    /' >&2
        if [[ "${__black_mode}" == "error" ]]; then
            return 1
        fi
    else
        echo "done"
    fi
fi
