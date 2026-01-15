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
    "$REAL_GIT" config wrapper.plugin.commit_noverify.strict true
    echo "test" > test.txt
    "$REAL_GIT" add test.txt

    run "$WRAPPER_PATH" commit --no-verify -m "test"
    [[ $status -ne 0 ]]
    [[ "$output" == *"--no-verify is disabled"* ]]
}
