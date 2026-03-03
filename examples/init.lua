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
