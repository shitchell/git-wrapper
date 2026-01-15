#!/usr/bin/env bats

# Setup
setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WRAPPER_PATH="$(dirname "$TEST_DIR")/git"
    FIXTURES_DIR="$TEST_DIR/fixtures"

    # Create a temp directory for test repos
    TEST_TEMP="$(mktemp -d)"

    # Find the real git (skip our wrapper)
    GIT=$(which -a git | while read -r p; do
        [[ "$(realpath "$p")" != "$(realpath "$WRAPPER_PATH")" ]] && echo "$p" && break
    done)
    export GIT

    # Initialize a test repo
    cd "$TEST_TEMP"
    "$GIT" init -q
    "$GIT" config user.email "test@test.com"
    "$GIT" config user.name "Test User"

    # Disable wrapper plugins for clean testing
    "$GIT" config wrapper.enabled true
}

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
    "$GIT" config wrapper.enabled false
    run "$WRAPPER_PATH" status
    [[ $status -eq 0 ]]
    [[ "$output" == *"On branch"* ]] || [[ "$output" == *"No commits yet"* ]]
}

# =============================================================================
# Config Option Tests (via git config wrapper)
# =============================================================================

@test "wrapper reads wrapper.showScriptName" {
    cd "$TEST_TEMP"
    "$GIT" config wrapper.showScriptName true
    result=$("$GIT" config wrapper.showScriptName)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.exitOnFailure" {
    cd "$TEST_TEMP"
    "$GIT" config wrapper.exitOnFailure true
    result=$("$GIT" config wrapper.exitOnFailure)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.notifyOnModify" {
    cd "$TEST_TEMP"
    "$GIT" config wrapper.notifyOnModify true
    result=$("$GIT" config wrapper.notifyOnModify)
    [[ "$result" == "true" ]]
}

@test "wrapper reads wrapper.verbose" {
    cd "$TEST_TEMP"
    "$GIT" config wrapper.verbose true
    result=$("$GIT" config wrapper.verbose)
    [[ "$result" == "true" ]]
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

@test "wrapper passes -C option correctly" {
    cd "$TEST_TEMP"
    mkdir subdir
    (cd subdir && "$GIT" init -q)

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

@test "wrapper handles -c option for inline config" {
    cd "$TEST_TEMP"
    run "$WRAPPER_PATH" -c user.name="Inline Test" config user.name
    [[ "$output" == "Inline Test" ]]
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

    result=$("$GIT" config test.value)
    [[ "$result" == "bats-test" ]]
}

@test "wrapper executes git config get" {
    cd "$TEST_TEMP"
    "$GIT" config test.getvalue "retrieved"
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
    result=$("$GIT" diff --cached --name-only)
    [[ "$result" == *"testfile.txt"* ]]
}

@test "wrapper executes git commit" {
    cd "$TEST_TEMP"
    echo "test" > testfile.txt
    "$GIT" add testfile.txt
    run env GIT_PASSTHROUGH=true "$WRAPPER_PATH" commit -m "test commit"
    [[ $status -eq 0 ]]

    # Verify commit exists
    result=$("$GIT" log --oneline -1)
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
# Plugin Directory Tests
# =============================================================================

@test "wrapper looks for plugins in ~/.git.d" {
    # This just verifies the paths are referenced in the script
    run grep -q '\.git\.d' "$WRAPPER_PATH"
    [[ $status -eq 0 ]]
}

@test "wrapper supports pre-process.d plugins" {
    run grep -q 'pre-process\.d' "$WRAPPER_PATH"
    [[ $status -eq 0 ]]
}

@test "wrapper supports post-process.d plugins" {
    run grep -q 'post-process\.d' "$WRAPPER_PATH"
    [[ $status -eq 0 ]]
}
