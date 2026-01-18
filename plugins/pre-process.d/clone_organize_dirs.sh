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
# If `wrapper.forceOrganize` is set to true, the above goes out the window, and
# this plugin will ALWAYS organize a cloned repo.
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
        return 1
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
    for arg in "${GIT_SUBCOMMAND_ARGS[@]}"; do
        [[ "${arg}" == "-"* ]] && continue
        GIT_POSITIONAL_ARGS+=("${arg}")
    done
fi
CLONE_URL="${GIT_POSITIONAL_ARGS[0]}"
TARGET_DIRECTORY="${GIT_POSITIONAL_ARGS[1]}"
if [[ -n "${TARGET_DIRECTORY}" ]]; then
    if [[ "${GIT_TEST}" =~ ^"1"|"true"$ ]]; then
        echo "TARGET_DIRECTORY is set to '${TARGET_DIRECTORY}', exiting..."
    fi
    return 0
fi

# Parse out the host
HOST=""
__is_http=false
__is_ssh=false
if [[ "${CLONE_URL}" =~ ^https?://([^@]+@)?([^/:]+) ]]; then
    # Treat the URL as an HTTP URL
    HOST="${BASH_REMATCH[2]}"
    __is_http=true
elif [[ "${CLONE_URL}" =~ ^[^@]+@([^:]+) ]]; then
    # Treat the URL as an SSH URL
    HOST="${BASH_REMATCH[1]}"
    __is_ssh=true
elif [[ "${CLONE_URL}" =~ ^/ ]]; then
    # Local filepath, don't organize
    echo "WARNING: not organizing, local filepaths unsupported: ${CLONE_URL}"
    return 0
else
    # If we couldn't parse the host out, then skip this script
    echo "WARNING: Unable to parse host from clone URL: ${CLONE_URL}" >&2
    return 0
fi

[[ "${GIT_TEST}" =~ ^"1"|"true"$ ]] && echo "HOST: ${HOST}"

if [[ -z "${HOST}" ]]; then
    # Ignore for now
    echo "WARNING: Unable to parse host from clone URL: ${CLONE_URL}" >&2
    return 0
fi

# If we made it this far, then we have a host and need to start building the
# target directory. At the final stage, the target directory will be set to:
#   ${TARGET_DIRECTORY_BASE}/${TARGET_DIRECTORY_HOST}/${TARGET_DIRECTORY_SUFFIX}
# Where:
#   - TARGET_DIRECTORY_BASE is the base directory to organize all repos into
#   - TARGET_DIRECTORY_HOST is the host of the clone URL, optionally modified
#     below based on the host (e.g.: "ssh.dev.azure.com" -> "dev.azure.com")
#   - TARGET_DIRECTORY_SUFFIX is the host-specific path to the repo
#    (e.g.: "myorg/myrepo")
__using_default_base=false
TARGET_DIRECTORY_BASE=$(plugin-option basedir)
if [[ -z "${TARGET_DIRECTORY_BASE}" ]]; then
    # We intentionally do not use --default so that we can tell
    # if basedir is unset and let the user know to set it.
    __using_default_base=true
    TARGET_DIRECTORY_BASE="${HOME}/code/git"
fi
debug "TARGET_DIRECTORY_BASE: ${TARGET_DIRECTORY_BASE}"

# Based on the host, determine TARGET_DIRECTORY_SUFFIX and TARGET_DIRECTORY_HOST
TARGET_DIRECTORY_HOST="${HOST}"
TARGET_DIRECTORY_SUFFIX=""
case "${HOST}" in
    "dev.azure.com")
        # https://dev.azure.com/<org>/<project>/_git/<repo>
        if ${__is_http}; then
            # Parse out the organization and project
            if [[ "${CLONE_URL}" =~ ^https?://[^/]+/([^/]+)/([^/]+)/_git/(.*) ]]; then
                ORG="${BASH_REMATCH[1]}"
                PROJECT=$(urldecode "${BASH_REMATCH[2]}")
                REPO=$(urldecode "${BASH_REMATCH[3]%.git}")
                TARGET_DIRECTORY_SUFFIX="${ORG}/${PROJECT}/${REPO}"
            fi
        fi
        ;;
    "ssh.dev.azure.com")
        # git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
        if ${__is_ssh}; then
            # Parse out the organization and project
            if [[ "${CLONE_URL}" =~ ^[^@]+@[^:]+:v3/([^/]+)/([^/]+)/(.*) ]]; then
                ORG="${BASH_REMATCH[1]}"
                PROJECT=$(urldecode "${BASH_REMATCH[2]}")
                REPO=$(urldecode "${BASH_REMATCH[3]%.git}")
                TARGET_DIRECTORY_HOST="${HOST#ssh.}"
                TARGET_DIRECTORY_SUFFIX="${ORG}/${PROJECT}/${REPO}"
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
            if [[ "${CLONE_URL}" =~ ^https?://[^/]+/([^/]+)/([^/]+)(\.git)?/?$ ]]; then
                USER="${BASH_REMATCH[1]}"
                REPO=$(urldecode "${BASH_REMATCH[2]%.git}")
                TARGET_DIRECTORY_SUFFIX="${USER}/${REPO}"
            fi
        elif ${__is_ssh}; then
            # Parse out the organization/user and project
            if [[ "${CLONE_URL}" =~ ^[^@]+@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
                USER="${BASH_REMATCH[1]}"
                REPO=$(urldecode "${BASH_REMATCH[2]%.git}")
                TARGET_DIRECTORY_SUFFIX="${USER}/${REPO}"
            fi
        fi
        ;;
    "bitbucket.org")
        # https://bitbucket.org/<org>/<repo>.git
        # git@bitbucket.org:<org>/<repo>.git
        if ${__is_http}; then
            # Parse out the organization/user and project
            if [[ "${CLONE_URL}" =~ ^https?://[^/]+/([^/]+)/([^/]+)\.git$ ]]; then
                USER="${BASH_REMATCH[1]}"
                REPO=$(urldecode "${BASH_REMATCH[2]%.git}")
                TARGET_DIRECTORY_SUFFIX="${USER}/${REPO}"
            fi
        elif ${__is_ssh}; then
            # Parse out the organization/user and project
            if [[ "${CLONE_URL}" =~ ^[^@]+@[^:]+:([^/]+)/([^/]+)\.git$ ]]; then
                USER="${BASH_REMATCH[1]}"
                REPO=$(urldecode "${BASH_REMATCH[2]%.git}")
                TARGET_DIRECTORY_SUFFIX="${USER}/${REPO}"
            fi
        fi
        ;;
    *)
        echo "ERROR: unsupported host: ${HOST}" >&2
        return 0
        ;;
esac

# Check if we were able to set the target suffix
if [[ -z "${TARGET_DIRECTORY_SUFFIX}" ]]; then
    echo "ERROR: skipping: unable to parse '${HOST}' clone URL: ${CLONE_URL}" >&2
    return 0
fi

# Build the target directory
TARGET_DIRECTORY+="${TARGET_DIRECTORY_BASE}/"
TARGET_DIRECTORY+="${TARGET_DIRECTORY_HOST}/"
TARGET_DIRECTORY+="${TARGET_DIRECTORY_SUFFIX}"

debug "TARGET_DIRECTORY: ${TARGET_DIRECTORY}"

# Check if the target directory exists and is not empty
if [[
    -d "${TARGET_DIRECTORY}"
    && -n "$(ls -A "${TARGET_DIRECTORY}")"
]]; then
    # Ignore for now
    echo "WARNING: Target directory exists and is not empty: ${TARGET_DIRECTORY}" >&2
    echo "WARNING: To clone to this directory, manually run the following command:" >&2
    echo "WARNING:   git clone '${CLONE_URL}' '${TARGET_DIRECTORY}'" >&2
    return 1
fi

[[ "${GIT_TEST}" =~ ^"1"|"true"$ ]] && echo "TARGET_DIRECTORY: ${TARGET_DIRECTORY}"

# If we made it this far, then we have a full target path. If we had to use
# the default base directory, then warn the user
if ${__using_default_base}; then
    echo "WARNING: git.gitDirectory not set, using default git directory: ${TARGET_DIRECTORY_BASE}" >&2
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
mkdir -p "${TARGET_DIRECTORY}" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "ERROR: Unable to create target directory: ${TARGET_DIRECTORY}" >&2
    return 1
fi

# Update the git subcommand args
GIT_SUBCOMMAND_ARGS+=("${TARGET_DIRECTORY}")
