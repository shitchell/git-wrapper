#!/usr/bin/env bash
#
# Show a count of all ignored directories and files at the end of the status
# message
#
# Config (see `git` for how {plugin-key} is resolved):
#   {plugin-key}.enabled (bool): default true

# Exit if the git command failed
[[ ${GIT_EXIT_CODE} -ne 0 ]] && return ${GIT_EXIT_CODE}

# Only run when called from an interactive session and not in a pipe
[[ "${__STDOUT_PIPED}" == "true" || "${__IN_SCRIPT}" == "true" ]] && return 0

# Skip if repo has no commits (unborn HEAD)
"${GIT}" "${GIT_ARGS[@]}" rev-parse HEAD &>/dev/null || return 0

# Don't show the last line if `--ignored` is in the subcommands
__using_ignored=false
for arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
    [[ "${arg}" == "--ignored" ]] && __using_ignored=true && break
done

"${GIT}" "${GIT_ARGS[@]}" status --ignored --porcelain \
    | awk -v green="${C_GREEN}" -v rst="${S_RESET}" -v using_ignored="${__using_ignored}" '
        # If the filepath ends with a "/", then it is a directory
        /^!!.*\/$/ {
            dirs+=1
        }

        # If the filepath does not end with a "/", then it is a file
        /^!!.*[^\/]$/ {
            files+=1
        }

        # Print the directory and file counts
        END {
            printf("%d ignored directories, %d ignored files\n", dirs, files)
            if (using_ignored == "false" && (dirs || files)) {
                printf("View all ignored files with `%sgit status --ignored%s`\n",
                       green, rst)
            }
        }
    '
