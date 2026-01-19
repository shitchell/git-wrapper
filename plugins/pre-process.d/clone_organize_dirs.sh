#!/usr/bin/env bash
#
# Organize cloned directories based on the host, organization/user, and project.
#
# Config:
#   wrapper.plugin.clone_organize_dirs.enabled (bool): default true
#   wrapper.plugin.clone_organize_dirs.force (bool): force organize even in scripts
#   wrapper.plugin.clone_organize_dirs.basedir (string): base directory (default: ~/code/git)
#
# This plugin will do nothing if:
# - a target directory is specified, then this script will do nothing.
# - `git` is called from within a script (so as to not break installation
#    scripts that expect the repo to be cloned into the current directory).
#
# If `wrapper.plugin.clone_organize_dirs.force` is set to true, the above goes
# out the window, and this plugin will ALWAYS organize a cloned repo.
#
# Examples:
#
#   This will clone the repository into "$GITDIR/github.com/myorg/myrepo"
#   $ git clone https://github.com/myorg/myrepo.git
#
#   This will clone the repo into "./foo-bar"
#   $ git clone https://github.com/myorg/myrepo.git ./foo-bar

debug "_IN_SCRIPT = ${_IN_SCRIPT}"

# If CLAUDECODE environment variable exists, force organize
if [[ -n "${CLAUDECODE}" ]]; then
    GIT_ARGS+=(-c wrapper.plugin.clone_organize_dirs.force=true)
fi

if [[ "${_IN_SCRIPT}" == "true" ]]; then
    __force_organize=$(plugin-option --bool --default=false force)
    if ! ${__force_organize}; then
        debug "skipping: session is not interactive and force option is unset"
        return 0
    fi
fi

# @description Parse a URL encoded string into plain text
# @usage urldecode <string>
# @usage echo <string> | urldecode -
function urldecode() (
    local string="${1}"
    local LANG=C
    local IFS=

    if [[ "${string}" == "-" ]]; then
        string="$(cat && echo x)"
        string="${string%x}"
    fi

    if [[ -z "${string}" ]]; then
        return ${E_PRE_ERROR}
    fi

    # This is perhaps a risky gambit, but since all escape characters must be
    # encoded, we can replace %NN with \xNN and pass the lot to printf -b, which
    # will decode hex for us
    printf '%b' "${string//%/\\x}"
)

# For testing purposes, set GIT_SUBCOMMAND_ARGS to all args passed to
# this script except for the first one (which is the path to this script)
if [[ "${GIT_TEST}" =~ ^"1"|"true"$ ]]; then
    GIT_SUBCOMMAND_ARGS=("${@:1}")
    echo "TESTING WITH GIT_SUBCOMMAND_ARGS (${#GIT_SUBCOMMAND_ARGS[@]}):$(printf " '%s'" "${GIT_SUBCOMMAND_ARGS[@]}")"
fi

# Check if the target clone directory is specified by counting the number of
# positional arguments (if two positional arguments are given, then the second
# argument is the target directory)
## try to see if another extension has already determined the positional args
GIT_POSITIONAL_ARGS=( "${GIT_POSITIONAL_ARGS[@]}" )
if [[ -z "${GIT_POSITIONAL_ARGS[0]}" ]]; then
    ## determine the positional arguments
    GIT_POSITIONAL_ARGS=()
    for __arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
        [[ "${__arg}" == "-"* ]] && continue
        GIT_POSITIONAL_ARGS+=("${__arg}")
    done
fi
__clone_url="${GIT_POSITIONAL_ARGS[0]}"
__target_directory="${GIT_POSITIONAL_ARGS[1]}"
if [[ -n "${__target_directory}" ]]; then
    if [[ "${GIT_TEST}" =~ ^"1"|"true"$ ]]; then
        echo "__target_directory is set to '${__target_directory}', exiting..."
    fi
    return 0
fi

# Parse out the host
__host=""
__is_http=false
__is_ssh=false
if [[ "${__clone_url}" =~ ^https?://([^@]+@)?([^/:]+) ]]; then
    # Treat the URL as an HTTP URL
    __host="${BASH_REMATCH[2]}"
    __is_http=true
elif [[ "${__clone_url}" =~ ^[^@]+@([^:]+) ]]; then
    # Treat the URL as an SSH URL
    __host="${BASH_REMATCH[1]}"
    __is_ssh=true
elif [[ "${__clone_url}" =~ ^/ ]]; then
    # Local filepath, don't organize
    echo "WARNING: not organizing, local filepaths unsupported: ${__clone_url}"
    return 0
else
    # If we couldn't parse the host out, then skip this script
    echo "WARNING: Unable to parse host from clone URL: ${__clone_url}" >&2
    return 0
fi

[[ "${GIT_TEST}" =~ ^"1"|"true"$ ]] && echo "__host: ${__host}"

if [[ -z "${__host}" ]]; then
    # Ignore for now
    echo "WARNING: Unable to parse host from clone URL: ${__clone_url}" >&2
    return 0
fi

# If we made it this far, then we have a host and need to start building the
# target directory. At the final stage, the target directory will be set to:
#   ${__target_directory_base}/${__target_directory_host}/${__target_directory_suffix}
# Where:
#   - __target_directory_base is the base directory to organize all repos into
#   - __target_directory_host is the host of the clone URL, optionally modified
#     below based on the host (e.g.: "ssh.dev.azure.com" -> "dev.azure.com")
#   - __target_directory_suffix is the host-specific path to the repo
#    (e.g.: "myorg/myrepo")
__using_default_base=false
__target_directory_base=$(plugin-option basedir)
if [[ -z "${__target_directory_base}" ]]; then
    # We intentionally do not use --default so that we can tell
    # if basedir is unset and let the user know to set it.
    __using_default_base=true
    __target_directory_base="${HOME}/code/git"
fi
debug "__target_directory_base: ${__target_directory_base}"

# Based on the host, determine __target_directory_suffix and __target_directory_host
__target_directory_host="${__host}"
__target_directory_suffix=""
case "${__host}" in
    "dev.azure.com")
        # https://dev.azure.com/<org>/<project>/_git/<repo>
        if ${__is_http}; then
            # Parse out the organization and project
            if [[ "${__clone_url}" =~ ^https?://[^/]+/([^/]+)/([^/]+)/_git/(.*) ]]; then
                __org="${BASH_REMATCH[1]}"
                __project=$(urldecode "${BASH_REMATCH[2]}")
                __repo=$(urldecode "${BASH_REMATCH[3]%.git}")
                __target_directory_suffix="${__org}/${__project}/${__repo}"
            fi
        fi
        ;;
    "ssh.dev.azure.com")
        # git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
        if ${__is_ssh}; then
            # Parse out the organization and project
            if [[ "${__clone_url}" =~ ^[^@]+@[^:]+:v3/([^/]+)/([^/]+)/(.*) ]]; then
                __org="${BASH_REMATCH[1]}"
                __project=$(urldecode "${BASH_REMATCH[2]}")
                __repo=$(urldecode "${BASH_REMATCH[3]%.git}")
                __target_directory_host="${__host#ssh.}"
                __target_directory_suffix="${__org}/${__project}/${__repo}"
            fi
        fi
        ;;
    "github.com" | *"gitlab"*)
        # https://<host>/<user>/<repo>.git
        # https://<host>/<org>/<repo>
        # git@<host>:<user>/<repo>.git
        # git@<host>:<org>/<repo>
        if ${__is_http}; then
            # Parse out the organization/user and project
            if [[ "${__clone_url}" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?/?$ ]]; then
                __user="${BASH_REMATCH[1]}"
                __repo=$(urldecode "${BASH_REMATCH[2]%.git}")
                __target_directory_suffix="${__user}/${__repo}"
            fi
        elif ${__is_ssh}; then
            # Parse out the organization/user and project
            if [[ "${__clone_url}" =~ ^[^@]+@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
                __user="${BASH_REMATCH[1]}"
                __repo=$(urldecode "${BASH_REMATCH[2]%.git}")
                __target_directory_suffix="${__user}/${__repo}"
            fi
        fi
        ;;
    "bitbucket.org")
        # https://bitbucket.org/<org>/<repo>[.git]
        # git@bitbucket.org:<org>/<repo>[.git]
        if ${__is_http}; then
            # Parse out the organization/user and project
            if [[ "${__clone_url}" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?/?$ ]]; then
                __user="${BASH_REMATCH[1]}"
                __repo=$(urldecode "${BASH_REMATCH[2]%.git}")
                __target_directory_suffix="${__user}/${__repo}"
            fi
        elif ${__is_ssh}; then
            # Parse out the organization/user and project
            if [[ "${__clone_url}" =~ ^[^@]+@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
                __user="${BASH_REMATCH[1]}"
                __repo=$(urldecode "${BASH_REMATCH[2]%.git}")
                __target_directory_suffix="${__user}/${__repo}"
            fi
        fi
        ;;
    *)
        echo "ERROR: unsupported host: ${__host}" >&2
        return 0
        ;;
esac

# Check if we were able to set the target suffix
if [[ -z "${__target_directory_suffix}" ]]; then
    echo "ERROR: skipping: unable to parse '${__host}' clone URL: ${__clone_url}" >&2
    return 0
fi

# Build the target directory
__target_directory+="${__target_directory_base}/"
__target_directory+="${__target_directory_host}/"
__target_directory+="${__target_directory_suffix}"

debug "__target_directory: ${__target_directory}"

# Check if the target directory exists and is not empty
if [[
    -d "${__target_directory}"
    && -n "$(ls -A "${__target_directory}")"
]]; then
    # Ignore for now
    echo "WARNING: Target directory exists and is not empty: ${__target_directory}" >&2
    echo "WARNING: To clone to this directory, manually run the following command:" >&2
    echo "WARNING:   git clone '${__clone_url}' '${__target_directory}'" >&2
    return ${E_PRE_ERROR}
fi

[[ "${GIT_TEST}" =~ ^"1"|"true"$ ]] && echo "__target_directory: ${__target_directory}"

# If we made it this far, then we have a full target path. If we had to use
# the default base directory, then warn the user
if ${__using_default_base}; then
    echo "WARNING: wrapper.plugin.clone_organize_dirs.basedir not set, using default: ${__target_directory_base}" >&2
    # Give them time to cancel
    printf "..."
    sleep 1
    printf "\r.. \b"
    sleep 1
    printf "\r.  \b\b"
    sleep 1
    printf "\r   \b\b\b"
fi

# Make sure the target directory exists
if ! mkdir -p "${__target_directory}" 2>/dev/null; then
    echo "ERROR: Unable to create target directory: ${__target_directory}" >&2
    return ${E_PRE_ERROR}
fi

# Update the git subcommand args
GIT_SUBCOMMAND_ARGS+=("${__target_directory}")
