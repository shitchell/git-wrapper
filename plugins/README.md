# Sample Plugins

Ready-to-use plugins for the git wrapper.

## Installation

Copy plugins to your `~/.git.d/` directory:

```bash
cp pre-process.d/commit_bashsyntaxcheck.sh ~/.git.d/pre-process.d/
cp post-process.d/commit_todo_check.sh ~/.git.d/post-process.d/
```

## Configuration

All plugins support `enabled` (default: `true`). Plugin-specific options use the format:

```bash
git config wrapper.plugin.<plugin_name>.<option> <value>
```

Or in `.gitconfig`:

```ini
[wrapper "plugin.commit_pyblack"]
    enabled = true
    mode = error
```

---

## Pre-process Plugins

### commit_bashsyntaxcheck.sh

Validate bash syntax with `bash -n` before commit. Checks `.sh` files and files with bash shebangs.

### commit_pyblack.sh

Run black on staged Python files.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mode` | string | `warn` | `warn` to show issues, `error` to block commit |

### commit_claude.sh

Set commit author and GPG options when run inside Claude Code (when `CLAUDECODE` env var is set).

### commit_noverify.sh

Block `--no-verify` from bypassing git hooks.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `strict` | bool | `false` | Block `--no-verify` when true |

![No-verify blocked](../screenshots/noverify.png)

### clone_organize_dirs.sh

Organize cloned repos into `basedir/host/user/repo` structure.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `basedir` | string | `~/code/git` | Base directory for organized repos |
| `force` | bool | `false` | Organize even when called from scripts |

![Clone organize](../screenshots/clone-organize.png)

---

## Post-process Plugins

### commit_todo_check.sh

Warn about TODOs in committed code.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `regex` | string | `\bTODO:` | Pattern to match TODO comments |

### commit_wip_check.sh

Check for WIP markers in committed code.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `regex` | string | `(#\|//\|\*).*\bWIP\b` | Pattern to match WIP comments |

### status_ignore_count.sh

Show count of ignored files after `git status`. Only runs in interactive sessions.

### push_jedi.sh

Print a blessing after force pushes (`--force`, `-f`, `--force-with-lease`, `--force-if-includes`). And also with you.

![May the force be with you](../screenshots/push-jedi.png)
