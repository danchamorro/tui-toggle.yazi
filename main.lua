--- @since 25.5.31

local TITLE = "tui-toggle"
local DEFAULT_DETACH_HINT = "Detach: Ctrl+B then D"

local get_cwd = ya.sync(function()
	local current = cx and cx.active and cx.active.current
	if current and current.cwd then
		return tostring(current.cwd.path or current.cwd)
	end
	return nil
end)

local function notify(level, title, content, timeout)
	ya.notify({
		title = title,
		content = content,
		level = level,
		timeout = timeout or 4,
	})
end

local function trim(value)
	return (value or ""):gsub("%s+$", "")
end

local function djb2_hash(input)
	local hash = 5381
	for i = 1, #input do
		hash = (hash * 33 + input:byte(i)) % 4294967296
	end
	return string.format("%08x", hash)
end

local function sanitize_prefix(prefix)
	local clean = tostring(prefix or "app"):gsub("[^%w_-]", "-")
	if clean == "" then
		return "app"
	end
	return clean
end

local function build_defaults()
	return {
		default_app = "pi",
		show_hints = true,
		apps = {
			pi = {
				cmd = "pi",
				tmux = true,
				scope = "dir",
				session_prefix = "pi",
				detach_hint = DEFAULT_DETACH_HINT,
				env = {
					TERM = "xterm-256color",
				},
			},
			shell = {
				cmd = os.getenv("SHELL") or "sh",
				tmux = true,
				scope = "dir",
				session_prefix = "shell",
				detach_hint = DEFAULT_DETACH_HINT,
			},
		},
	}
end

local function merge_tables(base, override)
	if type(override) ~= "table" then
		return base
	end

	for key, value in pairs(override) do
		if type(value) == "table" and type(base[key]) == "table" then
			base[key] = merge_tables(base[key], value)
		else
			base[key] = value
		end
	end

	return base
end

local function ensure_state(state)
	if state.__initialized then
		return
	end

	local defaults = build_defaults()
	state.default_app = defaults.default_app
	state.show_hints = defaults.show_hints
	state.apps = defaults.apps
	state.__initialized = true
end

local function command_succeeded(binary, args)
	local output = Command(binary)
		:arg(args)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	return output and output.status and output.status.success
end

local function has_tmux()
	return command_succeeded("tmux", "-V")
end

local function build_session_name(prefix, scope, cwd)
	local session_prefix = sanitize_prefix(prefix)
	if scope == "global" then
		return session_prefix
	end
	return string.format("%s-%s", session_prefix, djb2_hash(cwd))
end

local function tmux_has_session(session_name)
	return command_succeeded("tmux", { "has-session", "-t", session_name })
end

local function spawn_with_inherited_io(cmd)
	return cmd
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:spawn()
end

local function run_child(child, err_code, title)
	if not child then
		notify("error", title, "Failed to spawn process: " .. tostring(err_code), 5)
		return
	end

	local output, wait_err = child:wait_with_output()
	if wait_err ~= nil then
		notify("error", title, "Process failed: " .. tostring(wait_err), 5)
		return
	end

	if output and output.status and not output.status.success then
		local code = tostring(output.status.code)
		local stderr = trim(output.stderr)
		if stderr ~= "" then
			notify("error", title, string.format("Exited with code %s\n%s", code, stderr), 6)
		else
			notify("error", title, "Exited with code " .. code, 5)
		end
	end
end

local function spawn_tmux_attach(session_name)
	return spawn_with_inherited_io(Command("tmux"):arg({ "attach", "-t", session_name }))
end

local function spawn_tmux_new_session(app, session_name, cwd)
	local cmd = Command("tmux"):arg({ "new-session", "-s", session_name, "-c", cwd })

	if type(app.env) == "table" then
		for key, value in pairs(app.env) do
			cmd:arg({ "-e", string.format("%s=%s", key, value) })
		end
	end

	cmd:arg(app.cmd)
	if type(app.args) == "table" and #app.args > 0 then
		cmd:arg(app.args)
	end

	return spawn_with_inherited_io(cmd)
end

local function spawn_tmux_session(app_name, app, cwd, scope, show_hints)
	if not has_tmux() then
		notify("error", TITLE, "tmux is not installed or not in PATH", 5)
		return
	end

	local session_name = build_session_name(app.session_prefix or app_name, scope, cwd)

	if show_hints and app.detach_hint then
		notify("info", TITLE, app.detach_hint, 3)
	end

	local child, err_code
	if tmux_has_session(session_name) then
		child, err_code = spawn_tmux_attach(session_name)
	else
		child, err_code = spawn_tmux_new_session(app, session_name, cwd)
	end

	run_child(child, err_code, TITLE)
end

local function spawn_direct(app, cwd)
	local cmd = Command(app.cmd):cwd(cwd)

	if type(app.env) == "table" then
		for key, value in pairs(app.env) do
			cmd:env(key, tostring(value))
		end
	end

	if type(app.args) == "table" and #app.args > 0 then
		cmd:arg(app.args)
	end

	local child, err_code = spawn_with_inherited_io(cmd)
	run_child(child, err_code, TITLE)
end

local function list_apps(apps)
	local names = {}
	for name, _ in pairs(apps) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function normalize_scope(scope)
	if scope == "dir" or scope == "global" then
		return scope
	end

	notify("warn", TITLE, "Invalid scope; using `dir`", 3)
	return "dir"
end

return {
	setup = function(state, opts)
		ensure_state(state)
		opts = opts or {}

		if type(opts.default_app) == "string" and opts.default_app ~= "" then
			state.default_app = opts.default_app
		end

		if opts.show_hints ~= nil then
			state.show_hints = opts.show_hints == true
		end

		if type(opts.apps) == "table" then
			state.apps = merge_tables(state.apps, opts.apps)
		end
	end,

	entry = function(state, job)
		ensure_state(state)

		job = job or {}
		local args = job.args or {}
		local app_name = args[1] or state.default_app or "pi"
		local app = state.apps[app_name]

		if type(app) ~= "table" then
			notify("error", TITLE, string.format("Unknown app `%s`. Available: %s", app_name, list_apps(state.apps)), 6)
			return
		end

		if type(app.cmd) ~= "string" or app.cmd == "" then
			notify("error", TITLE, string.format("App `%s` is missing `cmd`", app_name), 5)
			return
		end

		local cwd = get_cwd()
		if not cwd or cwd == "" then
			notify("error", TITLE, "Unable to determine current Yazi directory", 5)
			return
		end

		local _permit = ui.hide and ui.hide() or ya.hide()
		local scope = normalize_scope(args.scope or app.scope or "dir")

		if app.tmux then
			spawn_tmux_session(app_name, app, cwd, scope, state.show_hints)
		else
			spawn_direct(app, cwd)
		end
	end,
}
