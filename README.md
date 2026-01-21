# git-wrapper

A custom git wrapper that runs plugins before or after git commands. Plugins can modify arguments, disable command execution, or react to git commands.

![TODO check example](screenshots/todo-check.png)

## Installation

### Using the Install Script

```bash
git clone git@github.com:shitchell/git-wrapper.git
cd git-wrapper
./install.sh              # basic install
./install.sh --with-plugins  # include sample plugins
./install.sh --dry-run    # preview what will be done
```

The script symlinks the wrapper to `~/.local/bin/git`, creates the plugin directories at `~/.git.d/`, and sets `wrapper.scriptDir` in your git config. Use `--bin-dir` and `--config-dir` to customize locations.

### Manual Installation

```bash
# Clone the repo
git clone git@github.com:shitchell/git-wrapper.git
cd git-wrapper

# Symlink the wrapper to a directory in your PATH. It must come BEFORE
# /usr/bin so that typing `git` runs the wrapper instead of the system git.
# ~/.local/bin is a common choice and is often already in PATH.
ln -s "$(pwd)/bin/git" ~/.local/bin/git

# Ensure ~/.local/bin is in PATH (add to ~/.bashrc if not already there)
export PATH="$HOME/.local/bin:$PATH"

# Create the plugin directories. Pre-process plugins run before git commands,
# post-process plugins run after. Scripts must be executable.
mkdir -p ~/.git.d/pre-process.d
mkdir -p ~/.git.d/post-process.d

# (Optional) Tell git where to find the plugin directories. This is only
# needed if you use a non-default location (something other than ~/.git.d).
git config --global wrapper.scriptDir ~/.git.d

# (Optional) Copy sample plugins from the repo
cp plugins/pre-process.d/*.sh ~/.git.d/pre-process.d/
cp plugins/post-process.d/*.sh ~/.git.d/post-process.d/
chmod +x ~/.git.d/pre-process.d/*.sh ~/.git.d/post-process.d/*.sh
```

## Configuration

All options are set via `git config`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `wrapper.enabled` | bool | `true` | Enable/disable the wrapper entirely |
| `wrapper.scriptDir` | path | `~/.git.d` | Directory containing plugin scripts |
| `wrapper.showScriptName` | bool | `false` | Prefix plugin output with plugin name |
| `wrapper.exitOnFailure` | bool | `false` | Exit if a plugin fails |
| `wrapper.notifyOnModify` | bool | `false` | Show message when plugin sets `OUTPUT_MODIFIED=true` |
| `wrapper.verbose` | bool | `false` | Enable both `showScriptName` and `notifyOnModify` |

Example:
```bash
git config --global wrapper.verbose true
git config --global wrapper.exitOnFailure true
```

### Passthrough

Skip the wrapper entirely:
```bash
# Via environment variable
GIT_PASSTHROUGH=true git status

# Via config (useful for specific repos)
git config wrapper.enabled false
```

**Note:** `GIT_PASSTHROUGH` is checked at the very top of the script before anything else loads - it's the most efficient way to bypass the wrapper. `wrapper.enabled` requires the script to load functions, parse arguments, and read config before it can check the setting. Use `GIT_PASSTHROUGH` for performance-sensitive scenarios (e.g., scripts that call git repeatedly); use `wrapper.enabled` for convenience when you want to disable the wrapper for a specific repo via config.

## Plugin Configuration

Plugins use git config subsections for their settings:

```ini
[wrapper "plugin.commit_pyblack"]
    enabled = false
    mode = error

[wrapper "plugin.clone_organize_dirs"]
    basedir = ~/projects
```

Or via command line:
```bash
# Disable a plugin
git config wrapper.plugin.commit_pyblack.enabled false

# Set plugin options
git config wrapper.plugin.commit_pyblack.mode error
git config wrapper.plugin.clone_organize_dirs.basedir ~/projects
```

All plugins support `enabled` (default: `true`). Plugin-specific options are documented below.

## Writing Plugins

Plugins are bash scripts placed in `~/.git.d/pre-process.d/` or `~/.git.d/post-process.d/`.

### Naming Standards

- `{subcommand}.sh` - anonymous plugin for a subcommand (e.g., `commit.sh`)
- `{subcommand}_{name}.sh` - named plugin for a subcommand (e.g., `commit_lint.sh`)
- `{number}_{name}.sh` - runs for all subcommands (e.g., `10_log.sh`)

Plugins are discovered via glob patterns and run in glob order (alphabetical). For subcommand-specific plugins, `commit.sh` runs before `commit_lint.sh`. Numbered global plugins run after subcommand-specific ones, sorted alphabetically by filename (so `05_early.sh` runs before `10_log.sh`).

### Available Variables

Plugins are sourced (not executed), so they have access to:

| Variable | Description |
|----------|-------------|
| `GIT` | Path to the real git binary |
| `GIT_ARGS` | Array of git options (before subcommand) |
| `GIT_SUBCOMMAND` | The git subcommand (e.g., `commit`, `push`) |
| `GIT_SUBCOMMAND_ARGS` | Array of arguments after the subcommand |
| `GIT_EXIT_CODE` | Exit code from git (post-process only) |
| `RUN_GIT_CMD` | Set to `false` in pre-process to skip git execution |
| `OUTPUT_MODIFIED` | Set to `true` if plugin modified output |
| `USE_COLOR` | Whether color output is enabled |
| `__STDOUT_PIPED` | `true` if stdout is being piped |
| `__IN_SCRIPT` | `true` if git is being called from a script |
| `__PLUGIN_NAME` | Current plugin name (filename without `.sh`) |

### Helper Functions

| Function | Description |
|----------|-------------|
| `plugin-option [--TYPE] [--default VAL] KEY` | Read `wrapper.plugin.<plugin>.<key>` |
| `wrapper-option [--TYPE] [--default VAL] KEY` | Read `wrapper.<key>` |
| `git-option [--TYPE] [--default VAL] KEY` | Read any git config key |
| `warn MSG` | Print `warning: MSG` to stderr |
| `error MSG` | Print `error: MSG` to stderr |
| `fatal MSG` | Print `fatal: MSG` to stderr |
| `debug MSG` | Print debug message when `DEBUG=true` |

Type options: `--bool`, `--int`, `--bool-or-int`, `--path`, `--expiry-date`, `--color`

### Color Variables

When `USE_COLOR` is true, these are available:

```bash
$C_RED $C_GREEN $C_YELLOW $C_BLUE $C_MAGENTA $C_CYAN
$S_BOLD $S_DIM $S_RESET
```

See `bin/git` for the full list of available color and style variables (includes BLACK, WHITE, backgrounds, ITALIC, UNDERLINE, etc.).

### Example: Pre-process Plugin

```bash
#!/usr/bin/env bash
# ~/.git.d/pre-process.d/commit_secrets.sh
# Block commits containing potential secrets

patterns=(
    'AKIA[0-9A-Z]{16}'           # AWS access key
    '-----BEGIN .* PRIVATE KEY'  # Private keys
    'password\s*=\s*["\047][^"\047]+'  # password = "..."
)

staged=$("${GIT}" diff --cached --name-only)
for pattern in "${patterns[@]}"; do
    if "${GIT}" diff --cached | grep -qE "${pattern}"; then
        echo "error: staged changes may contain secrets (${pattern})" >&2
        RUN_GIT_CMD=false
        return 1
    fi
done
```

### Example: Post-process Plugin

```bash
#!/usr/bin/env bash
# ~/.git.d/post-process.d/push_notify.sh
# Send notification after push

if [[ ${GIT_EXIT_CODE} -eq 0 ]]; then
    notify-send "Git" "Push completed successfully"
fi
```

## Sample Plugins

The `plugins/` directory includes ready-to-use plugins. See [plugins/README.md](plugins/README.md) for details.

To use a plugin:
```bash
cp plugins/pre-process.d/commit_bashsyntaxcheck.sh ~/.git.d/pre-process.d/
```

| Plugin | Description |
|--------|-------------|
| `commit_bashsyntaxcheck.sh` | Validate bash syntax before commit |
| `commit_pyblack.sh` | Check Python formatting with black |
| `commit_claude.sh` | Set author/GPG for Claude Code sessions |
| `commit_noverify.sh` | Block `--no-verify` when strict mode enabled |
| `clone_organize_dirs.sh` | Organize repos by host/user/repo |
| `commit_todo_check.sh` | Warn about TODOs in committed code |
| `commit_wip_check.sh` | Check for WIP markers |
| `commit_trailing_whitespace.sh` | Check for trailing whitespace before commit |
| `status_ignore_count.sh` | Show ignored file count |
| `push_jedi.sh` | Bless force pushes |

![Clone organize example](screenshots/clone-organize.png)

## Running Tests

Tests use [bats](https://github.com/bats-core/bats-core):

```bash
bats tests/git-wrapper.bats
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (git and all plugins succeeded) |
| 1-79 | Git exit code (git failure always takes priority) |
| 80-99 | Pre-process plugin failed (custom code in range) |
| 100 | Pre-process plugin failed (returned invalid code) |
| 101-119 | Post-process plugin failed (custom code in range) |
| 120 | Post-process plugin failed (returned invalid code) |
| 128+ | Git exit code (fatal errors, signals) |

**Note:** If git fails, its exit code always takes priority over plugin exit codes.
Plugin exit code ranges (80-120) are chosen to not overlap with git's standard
exit codes (1-79, 128+).

## License

MIT
