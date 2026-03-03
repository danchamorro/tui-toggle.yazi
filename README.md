# tui-toggle.yazi

Toggle long-running TUIs from Yazi with persistent `tmux` sessions for `pi` and `shell`, with directory or global scopes.

![tui-toggle demo](assets/demo.gif)

## Features

- Per-directory `pi` and `shell` sessions (`scope = "dir"`)
- Optional global sessions (`scope = "global"`)
- Auto-reattach to existing sessions
- Detach from tmux-backed apps with `Ctrl+B` then `D`
- `shell` mode reattaches to the same shell session when reopened

## Requirements

- Yazi `>= 25.5.31`
- `tmux` (required for default `pi` and `shell` modes)

## Platform support

Current reality for this first release:

- **Tested:** macOS
- **Expected to work:** Linux (with `tmux` installed)
- **Untested:** Windows

Notes:

- Default `pi` and `shell` modes depend on `tmux`.
- If you're on Windows, prefer using this plugin in WSL until native Windows behavior is validated.

### Ghostty note (macOS)

If `Shift+Enter` doesn't insert a newline in PI while running inside tmux, add this to your Ghostty config (`~/Library/Application Support/com.mitchellh.ghostty/config`):

```ini
# Map Shift+Enter to LF (Ctrl+J)
keybind = shift+enter=text:\x0a
```

Then restart Ghostty and restart tmux sessions (`tmux kill-server`).

Recommended `~/.tmux.conf`:

```tmux
set -g default-terminal "xterm-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Pass modified keys (like Shift+Enter) through tmux
set -g xterm-keys on
set -s extended-keys on
set -as terminal-features ",xterm-256color:extkeys"

# Better scrollback experience with interactive TUIs like pi
set -g mouse on
set -g history-limit 100000
setw -g mode-keys vi

# Optional: keep tmux UI minimal
set -g status off
```

Without these settings, mouse-wheel scrolling inside a tmux-backed TUI can be captured by the app as input history navigation instead of tmux scrollback.

## Install

### Local development

```bash
mkdir -p ~/.config/yazi/plugins/tui-toggle.yazi
cp main.lua ~/.config/yazi/plugins/tui-toggle.yazi/main.lua
```

### After publishing

```bash
ya pkg add danchamorro/tui-toggle
```

## Migrating from v1

In v1, `shell` mode spawned a direct (non-tmux) shell that required `exit` to return to Yazi. Starting in v2, `shell` defaults to `tmux = true` for persistent, detachable sessions -- the same behavior `pi` has always had.

**What changed:**

- `shell` now requires `tmux` by default.
- Detach with `Ctrl+B` then `D` instead of `exit`.
- Reattach to the same shell session by triggering the keymap again.

**If you do not have tmux installed** and want the old direct-shell behavior, override in your `init.lua`:

```lua
require("tui-toggle"):setup({
	apps = {
		shell = {
			tmux = false,
		},
	},
})
```

## Session scopes

`tui-toggle` supports two session scopes for tmux-backed apps like `pi` and `shell`:

- `scope = "dir"` (default): one session per directory (project-isolated)
- `scope = "global"`: one shared session reused across directories

Examples:

- `plugin tui-toggle -- pi` -> directory-scoped session (e.g. `pi-<hash>`)
- `plugin tui-toggle -- pi --scope=global` -> shared global session (`pi`)
- `plugin tui-toggle -- shell` -> directory-scoped shell session (e.g. `shell-<hash>`)
- `plugin tui-toggle -- shell --scope=global` -> shared global shell session (`shell`)

## Keymaps

Add to `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = ["g", "p"]
run  = "plugin tui-toggle -- pi"
desc = "Toggle pi (detach with Ctrl+B then D)"

[[mgr.prepend_keymap]]
on   = ["g", "G"]
run  = "plugin tui-toggle -- pi --scope=global"
desc = "Toggle global pi session"

[[mgr.prepend_keymap]]
on   = ["g", "t"]
run  = "plugin tui-toggle -- shell"
desc = "Toggle directory shell session (detach with Ctrl+B then D)"

[[mgr.prepend_keymap]]
on   = ["g", "T"]
run  = "plugin tui-toggle -- shell --scope=global"
desc = "Toggle global shell session"
```

Tip: keep `scope = "dir"` as the app default and use `--scope=global` in a dedicated keymap when you want one shared shell.

## Optional setup

In `~/.config/yazi/init.lua`:

```lua
require("tui-toggle"):setup({
	default_app = "pi",
	show_hints = true,
	apps = {
		pi = {
			cmd = "pi",
			tmux = true,
			scope = "dir",
			session_prefix = "pi",
			detach_hint = "Detach: Ctrl+B then D",
			env = { TERM = "xterm-256color" },
		},
		shell = {
			cmd = os.getenv("SHELL") or "sh",
			tmux = true,
			scope = "dir",
			session_prefix = "shell",
			detach_hint = "Detach: Ctrl+B then D",
		},
	},
})
```

## Cleanup on Yazi exit

Yazi plugins do not provide a universal lifecycle hook for cleanup on process exit. Keep cleanup in your shell wrapper:

```bash
_cleanup_tui_toggle_tmux_sessions() {
  local session
  tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r session; do
    [[ "$session" == pi || "$session" == pi-* || "$session" == shell || "$session" == shell-* ]] || continue
    tmux kill-session -t "$session" 2>/dev/null
  done
}

yazi() {
  command yazi "$@"
  local exit_code=$?
  _cleanup_tui_toggle_tmux_sessions
  return $exit_code
}
```

## License

MIT
