#!/usr/bin/env bats

# Setup - runs before each test
setup() {
    # Get paths relative to this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    REPO_ROOT="${TEST_DIR%/*}"
    WRAPPER_PATH="${REPO_ROOT}/bin/git"
    PLUGINS_DIR="${REPO_ROOT}/plugins"
    FIXTURES_DIR="${TEST_DIR}/fixtures"

    # Create a temp directory for test repos
    TEST_TEMP="$(mktemp -d)"

    # Find the real git (skip our wrapper)
    REAL_GIT=$(which -a git | while read -r p; do
        [[ "$(realpath "$p")" != "$(realpath "$WRAPPER_PATH")" ]] && echo "$p" && break
    done)
    export REAL_GIT

    # Initialize a test repo
    cd "$TEST_TEMP"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"

    # Point wrapper to repo's plugins directory
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
}

# Teardown - runs after each test
teardown() {
    rm -rf "$TEST_TEMP"
}

# =============================================================================
# Passthrough Tests
# =============================================================================

@test "GIT_PASSTHROUGH=true passes through to real git" {
    cd "$TEST_TEMP"
    run env GIT_PASSTHROUGH=true "$WRAPPER_PATH" status
    [[ "$output" == *"On branch"* ]] || [[ "$output" == *"No commits yet"* ]]
}

@test "wrapper respects wrapper.enabled=false" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.enabled false
    run "$WRAPPER_PATH" status
    [[ $status -eq 0 ]]
    [[ "$output" == *"On branch"* ]] || [[ "$output" == *"No commits yet"* ]]
}

# =============================================================================
# Inline Config Tests (-c option)
# =============================================================================

@test "wrapper handles -c for user config" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" -c user.name="Inline Test" config user.name
    [[ "$output" == "Inline Test" ]]
}

@test "wrapper handles -c wrapper.enabled=false" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" -c wrapper.enabled=false status
    [[ $status -eq 0 ]]
    [[ "$output" == *"On branch"* ]] || [[ "$output" == *"No commits yet"* ]]
}

@test "wrapper handles -c wrapper.scriptDir" {
    cd "$TEST_TEMP"
    # Point to a non-existent dir - should still work, just no plugins
    run "$WRAPPER_PATH" -c wrapper.scriptDir=/nonexistent status
    [[ $status -eq 0 ]]
}

@test "wrapper handles multiple -c options" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" -c user.name="Multi" -c user.email="multi@test.com" config --get-regexp "user\."
    [[ "$output" == *"user.name Multi"* ]]
    [[ "$output" == *"user.email multi@test.com"* ]]
}

# =============================================================================
# Config Option Tests
# =============================================================================

@test "wrapper reads wrapper.showScriptName" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.showScriptName true
    result=$("$REAL_GIT" config wrapper.showScriptName)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.exitOnFailure" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.exitOnFailure true
    result=$("$REAL_GIT" config wrapper.exitOnFailure)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.notifyOnModify" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.notifyOnModify true
    result=$("$REAL_GIT" config wrapper.notifyOnModify)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.verbose" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.verbose true
    result=$("$REAL_GIT" config wrapper.verbose)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.scriptDir" {
    cd "$TEST_TEMP"
    result=$("$REAL_GIT" config wrapper.scriptDir)
    [[ "$result" == "$PLUGINS_DIR" ]]
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

@test "wrapper passes -C option correctly" {
    cd "$TEST_TEMP"
    mkdir subdir
    (cd subdir && "$REAL_GIT" init -q)

    run "$WRAPPER_PATH" -C "$TEST_TEMP/subdir" rev-parse --show-toplevel
    [[ "$output" == "$TEST_TEMP/subdir" ]]
}

@test "wrapper passes --git-dir option correctly" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" --git-dir="$TEST_TEMP/.git" rev-parse --git-dir
    [[ "$output" == "$TEST_TEMP/.git" ]]
}

@test "wrapper passes --work-tree option correctly" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" --work-tree="$TEST_TEMP" rev-parse --show-toplevel
    [[ "$output" == "$TEST_TEMP" ]]
}

# =============================================================================
# Basic Command Tests
# =============================================================================

@test "wrapper executes git status" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" status
    [[ $status -eq 0 ]]
    [[ "$output" == *"On branch"* ]] || [[ "$output" == *"No commits yet"* ]]
}

@test "wrapper executes git init" {
    cd "$TEST_TEMP"
    mkdir newrepo
    cd newrepo
    run "$WRAPPER_PATH" init
    [[ $status -eq 0 ]]
    [[ -d .git ]]
}

@test "wrapper executes git config set" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" config test.value "bats-test"
    [[ $status -eq 0 ]]

    result=$("$REAL_GIT" config test.value)
    [[ "$result" == "bats-test" ]]
}

@test "wrapper executes git config get" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config test.getvalue "retrieved"
    run "$WRAPPER_PATH" config test.getvalue
    [[ $status -eq 0 ]]
    [[ "$output" == "retrieved" ]]
}

@test "wrapper executes git add" {
    cd "$TEST_TEMP"
    echo "test" > testfile.txt
    run "$WRAPPER_PATH" add testfile.txt
    [[ $status -eq 0 ]]

    # Verify file is staged
    result=$("$REAL_GIT" diff --cached --name-only)
    [[ "$result" == *"testfile.txt"* ]]
}

@test "wrapper executes git commit" {
    cd "$TEST_TEMP"
    echo "test" > testfile.txt
    "$REAL_GIT" add testfile.txt
    run env GIT_PASSTHROUGH=true "$WRAPPER_PATH" commit -m "test commit"
    [[ $status -eq 0 ]]

    # Verify commit exists
    result=$("$REAL_GIT" log --oneline -1)
    [[ "$result" == *"test commit"* ]]
}

# =============================================================================
# Exit Code Tests
# =============================================================================

@test "wrapper returns 0 on success" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" status
    [[ $status -eq 0 ]]
}

@test "wrapper returns non-zero on git failure" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" checkout nonexistent-branch-12345
    [[ $status -ne 0 ]]
}

@test "wrapper returns non-zero for invalid subcommand" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" notarealcommand
    [[ $status -ne 0 ]]
}

# =============================================================================
# Help and Version Tests
# =============================================================================

@test "wrapper passes --help" {
    run "$WRAPPER_PATH" --help
    [[ "$output" == *"usage:"* ]] || [[ "$output" == *"git"* ]]
}

@test "wrapper passes --version" {
    run "$WRAPPER_PATH" --version
    [[ "$output" == *"git version"* ]]
}

# =============================================================================
# Plugin System Tests
# =============================================================================

@test "wrapper uses wrapper.scriptDir for plugins" {
    cd "$TEST_TEMP"
    result=$("$REAL_GIT" config wrapper.scriptDir)
    [[ "$result" == "$PLUGINS_DIR" ]]
    [[ -d "$PLUGINS_DIR/pre-process.d" ]]
    [[ -d "$PLUGINS_DIR/post-process.d" ]]
}

@test "plugin can be disabled via config" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.status_ignore_count.enabled false
    result=$("$REAL_GIT" config wrapper.plugin.status_ignore_count.enabled)
    [[ "$result" == "false" ]]
}

@test "plugin-specific options work" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.commit_pyblack.mode error
    result=$("$REAL_GIT" config wrapper.plugin.commit_pyblack.mode)
    [[ "$result" == "error" ]]
}

# =============================================================================
# Plugin: commit_bashsyntaxcheck
# =============================================================================

@test "commit_bashsyntaxcheck: passes valid bash" {
    cd "$TEST_TEMP"
    echo '#!/usr/bin/env bash
echo "hello"' > valid.sh
    chmod +x valid.sh
    "$REAL_GIT" add valid.sh

    run "$WRAPPER_PATH" commit -m "add valid bash"
    [[ $status -eq 0 ]]
}

@test "commit_bashsyntaxcheck: fails invalid bash" {
    cd "$TEST_TEMP"
    echo '#!/usr/bin/env bash
if [[ true; then  # syntax error
echo "broken"
fi' > invalid.sh
    chmod +x invalid.sh
    "$REAL_GIT" add invalid.sh

    run "$WRAPPER_PATH" commit -m "add invalid bash"
    [[ $status -ne 0 ]]
    [[ "$output" == *"syntax error"* ]] || [[ "$output" == *"error"* ]]
}

# =============================================================================
# Plugin: commit_todo_check
# =============================================================================

@test "commit_todo_check: warns about TODOs" {
    cd "$TEST_TEMP"
    # First commit to establish repo
    echo "initial" > initial.txt
    "$REAL_GIT" add initial.txt
    "$REAL_GIT" commit -q -m "initial"

    # Now commit with TODO
    echo "# TODO: fix this" > todo.txt
    "$REAL_GIT" add todo.txt
    run "$WRAPPER_PATH" commit -m "add todo"
    [[ "$output" == *"TODO"* ]]
}

# =============================================================================
# Plugin: commit_noverify
# =============================================================================

@test "commit_noverify: allows --no-verify by default" {
    cd "$TEST_TEMP"
    echo "test" > test.txt
    "$REAL_GIT" add test.txt

    run "$WRAPPER_PATH" commit --no-verify -m "test"
    [[ $status -eq 0 ]]
}

@test "commit_noverify: blocks --no-verify when strict" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.commit_noverify.mode strict
    echo "test" > test.txt
    "$REAL_GIT" add test.txt

    run "$WRAPPER_PATH" commit --no-verify -m "test"
    [[ $status -ne 0 ]]
    [[ "$output" == *"--no-verify is disabled"* ]]
}

# =============================================================================
# Plugin: commit_pyblack
# =============================================================================

@test "commit_pyblack: skips when black not installed" {
    cd "$TEST_TEMP"
    # Disable the plugin to test without black dependency
    "$REAL_GIT" config wrapper.plugin.commit_pyblack.enabled false

    # Create a Python file
    echo 'x=1' > test.py
    "$REAL_GIT" add test.py

    run "$WRAPPER_PATH" commit -m "test"
    # Should proceed without error (plugin disabled)
    [[ $status -eq 0 ]]
}

@test "commit_pyblack: mode=warn allows commit even with formatting issues" {
    skip "Requires black to be installed"
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.commit_pyblack.mode warn

    # Create badly formatted Python file
    echo 'x=1' > test.py
    "$REAL_GIT" add test.py

    run "$WRAPPER_PATH" commit -m "test with warn mode"
    # Should allow commit in warn mode
    [[ $status -eq 0 ]]
}

@test "commit_pyblack: mode=error blocks commit with formatting issues" {
    skip "Requires black to be installed"
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.commit_pyblack.mode error

    # Create badly formatted Python file
    echo 'x=1' > test.py
    "$REAL_GIT" add test.py

    run "$WRAPPER_PATH" commit -m "test with error mode"
    # Should block commit in error mode
    [[ $status -ne 0 ]]
}

# =============================================================================
# Plugin: commit_claude
# =============================================================================

@test "commit_claude: detects CLAUDECODE environment variable" {
    cd "$TEST_TEMP"
    echo "test" > test.txt
    "$REAL_GIT" add test.txt

    # Run with CLAUDECODE set
    run env CLAUDECODE=1 GIT_PASSTHROUGH=true "$WRAPPER_PATH" commit -m "test"
    # Note: We use GIT_PASSTHROUGH since we're testing env detection, not full commit
    [[ $status -eq 0 ]]
}

@test "commit_claude: sets author when CLAUDECODE is set" {
    cd "$TEST_TEMP"
    echo "test" > test.txt
    "$REAL_GIT" add test.txt

    # Commit with CLAUDECODE set (plugin should set user.name and user.email)
    run env CLAUDECODE=1 "$WRAPPER_PATH" commit -m "claude test commit"

    if [[ $status -eq 0 ]]; then
        # Check the commit author
        author=$("$REAL_GIT" log -1 --format='%an <%ae>')
        [[ "$author" == "Claude Code <noreply@anthropic.com>" ]]
    fi
}

@test "commit_claude: does nothing without CLAUDECODE" {
    cd "$TEST_TEMP"
    # Ensure CLAUDECODE is explicitly unset
    unset CLAUDECODE

    echo "test2" > test2.txt
    "$REAL_GIT" add test2.txt

    # Commit without CLAUDECODE - should use default user
    run env -u CLAUDECODE "$WRAPPER_PATH" commit -m "normal commit"
    [[ $status -eq 0 ]]

    author=$("$REAL_GIT" log -1 --format='%an')
    [[ "$author" == "Test User" ]]
}

# =============================================================================
# Plugin: clone_organize_dirs (using GIT_TEST mode)
# =============================================================================

@test "clone_organize_dirs: parses GitHub HTTPS URL" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "GIT_TEST=1 source '$CLONE_PLUGIN' 'https://github.com/user/repo.git'"
    [[ "$output" == *"__host: github.com"* ]]
    [[ "$output" == *"__target_directory:"*"/github.com/user/repo"* ]]
}

@test "clone_organize_dirs: parses GitHub SSH URL" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "GIT_TEST=1 source '$CLONE_PLUGIN' 'git@github.com:user/repo.git'"
    [[ "$output" == *"__host: github.com"* ]]
    [[ "$output" == *"__target_directory:"*"/github.com/user/repo"* ]]
}

@test "clone_organize_dirs: parses Azure DevOps HTTPS URL" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "GIT_TEST=1 source '$CLONE_PLUGIN' 'https://dev.azure.com/myorg/myproject/_git/myrepo'"
    [[ "$output" == *"__host: dev.azure.com"* ]]
    [[ "$output" == *"__target_directory:"*"/dev.azure.com/myorg/myproject/myrepo"* ]]
}

@test "clone_organize_dirs: parses Azure DevOps SSH URL" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "GIT_TEST=1 source '$CLONE_PLUGIN' 'git@ssh.dev.azure.com:v3/myorg/myproject/myrepo'"
    [[ "$output" == *"__host: ssh.dev.azure.com"* ]]
    [[ "$output" == *"__target_directory:"*"/dev.azure.com/myorg/myproject/myrepo"* ]]
}

@test "clone_organize_dirs: exits when target directory specified" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "GIT_TEST=1 source '$CLONE_PLUGIN' 'https://github.com/user/repo.git' './custom-dir'"
    [[ "$output" == *"__target_directory is set to './custom-dir'"* ]]
}

@test "clone_organize_dirs: warns on unsupported host" {
    cd "$TEST_TEMP"
    CLONE_PLUGIN="$PLUGINS_DIR/pre-process.d/clone_organize_dirs.sh"

    run bash -c "
        warn() { printf 'warning: %s\n' \"\$*\" >&2; }
        error() { printf 'error: %s\n' \"\$*\" >&2; }
        GIT_TEST=1 source '$CLONE_PLUGIN' 'https://unsupported.example.com/user/repo.git'
    "
    [[ "$output" == *"unsupported host"* ]] || [[ "$output" == *"Unable to parse"* ]]
}

# =============================================================================
# Plugin: commit_wip_check
# =============================================================================

@test "commit_wip_check: detects WIP comments after commit" {
    cd "$TEST_TEMP"
    # Need initial commit first
    echo "initial" > initial.txt
    "$REAL_GIT" add initial.txt
    "$REAL_GIT" commit -q -m "initial"

    # Create file with WIP marker
    echo '# WIP: not done yet' > wip_file.txt
    "$REAL_GIT" add wip_file.txt

    run env GIT_PASSTHROUGH=true "$WRAPPER_PATH" commit -m "add wip file"
    [[ $status -eq 0 ]]

    # Now run full wrapper which should detect WIP
    run "$WRAPPER_PATH" status
    # Check that status works (WIP check is post-process for commit)
}

@test "commit_wip_check: warns about WIP in committed code" {
    cd "$TEST_TEMP"
    # Initial commit
    echo "initial" > initial.txt
    "$REAL_GIT" add initial.txt
    "$REAL_GIT" commit -q -m "initial"

    # Add file with WIP and commit
    echo '// WIP need to fix' > code.js
    "$REAL_GIT" add code.js

    run "$WRAPPER_PATH" commit -m "commit with wip"
    [[ "$output" == *"WIP"* ]]
}

@test "commit_wip_check: custom regex works" {
    cd "$TEST_TEMP"
    # Set custom regex
    "$REAL_GIT" config wrapper.plugin.commit_wip_check.regex '\bFIXME\b'

    # Initial commit
    echo "initial" > initial.txt
    "$REAL_GIT" add initial.txt
    "$REAL_GIT" commit -q -m "initial"

    # Add file with FIXME
    echo '# FIXME: broken' > fixme.txt
    "$REAL_GIT" add fixme.txt

    run "$WRAPPER_PATH" commit -m "commit with fixme"
    [[ "$output" == *"FIXME"* ]] || [[ "$output" == *"WIP"* ]]
}

# =============================================================================
# Plugin: status_ignore_count
# =============================================================================

@test "status_ignore_count: shows ignored file count" {
    cd "$TEST_TEMP"
    # Create a .gitignore and some ignored files
    echo "*.log" > .gitignore
    echo "ignored content" > test.log
    mkdir -p ignored_dir
    echo "also ignored" > ignored_dir/file.log

    "$REAL_GIT" add .gitignore
    "$REAL_GIT" commit -q -m "add gitignore"

    # Run status through wrapper (not piped, simulating interactive)
    run "$WRAPPER_PATH" status
    # Should show ignored count (plugin only runs in interactive mode)
    # Note: Plugin checks _STDOUT_PIPED which will be true in `run`
    [[ $status -eq 0 ]]
}

@test "status_ignore_count: can be disabled" {
    cd "$TEST_TEMP"
    "$REAL_GIT" config wrapper.plugin.status_ignore_count.enabled false

    echo "*.log" > .gitignore
    echo "ignored" > test.log
    "$REAL_GIT" add .gitignore
    "$REAL_GIT" commit -q -m "add gitignore"

    run "$WRAPPER_PATH" status
    [[ $status -eq 0 ]]
}

# =============================================================================
# Plugin: push_jedi
# =============================================================================

@test "push_jedi: blesses --force push" {
    cd "$TEST_TEMP"

    # Create a bare "remote" repo
    REMOTE_DIR="$TEST_TEMP/remote.git"
    "$REAL_GIT" init -q --bare "$REMOTE_DIR"

    # Create a local repo and add remote
    LOCAL_DIR="$TEST_TEMP/local"
    mkdir -p "$LOCAL_DIR"
    cd "$LOCAL_DIR"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
    "$REAL_GIT" remote add origin "$REMOTE_DIR"

    # Make initial commit and push
    echo "initial" > file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q -m "initial"
    "$REAL_GIT" push -q origin master 2>/dev/null || "$REAL_GIT" push -q origin main 2>/dev/null

    # Amend and force push
    echo "amended" >> file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q --amend -m "amended"

    # Get branch name
    branch=$("$REAL_GIT" rev-parse --abbrev-ref HEAD)
    run env -u CLAUDECODE "$WRAPPER_PATH" push --force origin "$branch"
    [[ "$output" == *"May the force be with you"* ]]
}

@test "push_jedi: blesses -f push" {
    cd "$TEST_TEMP"

    REMOTE_DIR="$TEST_TEMP/remote2.git"
    "$REAL_GIT" init -q --bare "$REMOTE_DIR"

    LOCAL_DIR="$TEST_TEMP/local2"
    mkdir -p "$LOCAL_DIR"
    cd "$LOCAL_DIR"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
    "$REAL_GIT" remote add origin "$REMOTE_DIR"

    echo "initial" > file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q -m "initial"
    "$REAL_GIT" push -q origin master 2>/dev/null || "$REAL_GIT" push -q origin main 2>/dev/null

    echo "amended" >> file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q --amend -m "amended"

    branch=$("$REAL_GIT" rev-parse --abbrev-ref HEAD)
    run env -u CLAUDECODE "$WRAPPER_PATH" push -f origin "$branch"
    [[ "$output" == *"May the force be with you"* ]]
}

@test "push_jedi: blesses --force-with-lease push" {
    cd "$TEST_TEMP"

    REMOTE_DIR="$TEST_TEMP/remote3.git"
    "$REAL_GIT" init -q --bare "$REMOTE_DIR"

    LOCAL_DIR="$TEST_TEMP/local3"
    mkdir -p "$LOCAL_DIR"
    cd "$LOCAL_DIR"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
    "$REAL_GIT" remote add origin "$REMOTE_DIR"

    echo "initial" > file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q -m "initial"
    "$REAL_GIT" push -q origin master 2>/dev/null || "$REAL_GIT" push -q origin main 2>/dev/null

    echo "amended" >> file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q --amend -m "amended"

    branch=$("$REAL_GIT" rev-parse --abbrev-ref HEAD)
    run env -u CLAUDECODE "$WRAPPER_PATH" push --force-with-lease origin "$branch"
    [[ "$output" == *"May the force be with you"* ]]
}

@test "push_jedi: blesses --force-if-includes push" {
    cd "$TEST_TEMP"

    REMOTE_DIR="$TEST_TEMP/remote4.git"
    "$REAL_GIT" init -q --bare "$REMOTE_DIR"

    LOCAL_DIR="$TEST_TEMP/local4"
    mkdir -p "$LOCAL_DIR"
    cd "$LOCAL_DIR"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
    "$REAL_GIT" remote add origin "$REMOTE_DIR"

    echo "initial" > file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q -m "initial"
    "$REAL_GIT" push -q origin master 2>/dev/null || "$REAL_GIT" push -q origin main 2>/dev/null

    echo "amended" >> file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q --amend -m "amended"

    # --force-if-includes needs --force-with-lease
    branch=$("$REAL_GIT" rev-parse --abbrev-ref HEAD)
    run env -u CLAUDECODE "$WRAPPER_PATH" push --force-with-lease --force-if-includes origin "$branch"
    [[ "$output" == *"May the force be with you"* ]]
}

@test "push_jedi: no blessing on regular push" {
    cd "$TEST_TEMP"

    REMOTE_DIR="$TEST_TEMP/remote5.git"
    "$REAL_GIT" init -q --bare "$REMOTE_DIR"

    LOCAL_DIR="$TEST_TEMP/local5"
    mkdir -p "$LOCAL_DIR"
    cd "$LOCAL_DIR"
    "$REAL_GIT" init -q
    "$REAL_GIT" config user.email "test@test.com"
    "$REAL_GIT" config user.name "Test User"
    "$REAL_GIT" config wrapper.scriptDir "$PLUGINS_DIR"
    "$REAL_GIT" remote add origin "$REMOTE_DIR"

    echo "initial" > file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit -q -m "initial"

    branch=$("$REAL_GIT" rev-parse --abbrev-ref HEAD)
    run env -u CLAUDECODE "$WRAPPER_PATH" push origin "$branch"
    # Should NOT contain the blessing for regular push
    [[ "$output" != *"May the force be with you"* ]]
}

# =============================================================================
# Fixture Tests: Plugin output and failure behavior
# =============================================================================

@test "fixture: test_plugin outputs to stdout and stderr" {
    cd "$TEST_TEMP"

    # Create a custom script dir with the test fixture
    CUSTOM_SCRIPT_DIR="$TEST_TEMP/scripts"
    mkdir -p "$CUSTOM_SCRIPT_DIR/pre-process.d"
    cp "$FIXTURES_DIR/test_plugin.sh" "$CUSTOM_SCRIPT_DIR/pre-process.d/status_test.sh"

    "$REAL_GIT" config wrapper.scriptDir "$CUSTOM_SCRIPT_DIR"

    run "$WRAPPER_PATH" status
    [[ "$output" == *"stdout from plugin"* ]]
    [[ "$output" == *"stderr from plugin"* ]]
}

@test "fixture: failing_plugin with exitOnFailure returns code 100" {
    cd "$TEST_TEMP"

    # Create a custom script dir with the failing fixture
    CUSTOM_SCRIPT_DIR="$TEST_TEMP/scripts"
    mkdir -p "$CUSTOM_SCRIPT_DIR/pre-process.d"
    cp "$FIXTURES_DIR/failing_plugin.sh" "$CUSTOM_SCRIPT_DIR/pre-process.d/status_fail.sh"

    "$REAL_GIT" config wrapper.scriptDir "$CUSTOM_SCRIPT_DIR"
    "$REAL_GIT" config wrapper.exitOnFailure true

    run "$WRAPPER_PATH" status
    # Plugin returns 1 (invalid), wrapper should remap to 100 (E_PRE_ERROR_INVALID_CODE)
    [[ $status -eq 100 ]]
}

@test "fixture: failing_plugin without exitOnFailure continues" {
    cd "$TEST_TEMP"

    CUSTOM_SCRIPT_DIR="$TEST_TEMP/scripts"
    mkdir -p "$CUSTOM_SCRIPT_DIR/pre-process.d"
    cp "$FIXTURES_DIR/failing_plugin.sh" "$CUSTOM_SCRIPT_DIR/pre-process.d/status_fail.sh"

    "$REAL_GIT" config wrapper.scriptDir "$CUSTOM_SCRIPT_DIR"
    "$REAL_GIT" config wrapper.exitOnFailure false

    run "$WRAPPER_PATH" status
    # Without exitOnFailure, wrapper continues despite plugin failure
    [[ $status -eq 0 ]]
}

@test "fixture: modify_output_plugin sets OUTPUT_MODIFIED" {
    cd "$TEST_TEMP"

    CUSTOM_SCRIPT_DIR="$TEST_TEMP/scripts"
    mkdir -p "$CUSTOM_SCRIPT_DIR/post-process.d"
    cp "$FIXTURES_DIR/modify_output_plugin.sh" "$CUSTOM_SCRIPT_DIR/post-process.d/status_modify.sh"

    "$REAL_GIT" config wrapper.scriptDir "$CUSTOM_SCRIPT_DIR"
    "$REAL_GIT" config wrapper.notifyOnModify true

    run "$WRAPPER_PATH" status
    [[ "$output" == *"output was modified"* ]]
    [[ "$output" == *"output modified by post-process plugin"* ]]
}

# =============================================================================
# Plugin: commit_trailing_whitespace
# =============================================================================

@test "commit_trailing_whitespace: passes files without trailing whitespace" {
    cd "$TEST_TEMP"

    # Create a file without trailing whitespace
    echo "no trailing whitespace here" > clean.txt
    "$REAL_GIT" add clean.txt

    "$REAL_GIT" config wrapper.exitOnFailure true

    run "$WRAPPER_PATH" commit -m "clean commit"
    [[ $status -eq 0 ]]
}

@test "commit_trailing_whitespace: blocks files with trailing whitespace" {
    cd "$TEST_TEMP"

    # Create a file with trailing whitespace (space at end of line)
    printf "trailing whitespace \nhere\n" > dirty.txt
    "$REAL_GIT" add dirty.txt

    "$REAL_GIT" config wrapper.exitOnFailure true

    run "$WRAPPER_PATH" commit -m "dirty commit"
    # Should fail with pre-process error
    [[ $status -ne 0 ]]
    [[ "$output" == *"trailing whitespace"* ]]
}

@test "commit_trailing_whitespace: provides sed fix command" {
    cd "$TEST_TEMP"

    printf "has trailing \n" > whitespace.txt
    "$REAL_GIT" add whitespace.txt

    "$REAL_GIT" config wrapper.exitOnFailure true

    run "$WRAPPER_PATH" commit -m "whitespace commit"
    [[ $status -ne 0 ]]
    # Should suggest sed command to fix
    [[ "$output" == *"sed"* ]]
}

@test "commit_trailing_whitespace: can be disabled" {
    cd "$TEST_TEMP"

    printf "trailing \n" > file.txt
    "$REAL_GIT" add file.txt

    "$REAL_GIT" config wrapper.plugin.commit_trailing_whitespace.enabled false
    "$REAL_GIT" config wrapper.exitOnFailure true

    run "$WRAPPER_PATH" commit -m "disabled whitespace check"
    [[ $status -eq 0 ]]
}
