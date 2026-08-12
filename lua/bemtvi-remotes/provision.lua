-- The provisioning engine, shared by every backend (docker / ssh). Given a `backend`
-- descriptor (how to run a command on the remote, spawn the daemon, copy a file in) and a
-- URL, it: detects the remote's arch/OS (a reachability check + the platform key), resolves
-- the bemtvi daemon command on the remote (assume it is on the PATH, or fetch + install the
-- matching release binary), and returns the `btv.session.reconnect` spec that swaps the
-- window onto it. All external work runs over the LOCAL-ALWAYS seam (`btv.run_local` /
-- `btv.fs_local` / `btv.http.fetch_local`) — this machine is the one that dials the daemon, so
-- provisioning must happen here even when invoked from inside a remote session.

local M = {}

-- Trim surrounding whitespace.
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Progress on the message line, prefixed so it is clearly the connector talking.
local function progress(msg)
  btv.notify("remotes: " .. msg)
end
M._progress = progress

-- Map `uname -s` / `uname -m` to a release platform key (`"linux-x86_64"`, `"darwin-aarch64"`,
-- …). Fails LOUD on an OS/arch we publish no binary for, rather than fetching a 404.
function M.platform(os_name, machine)
  local os_key = ({ Linux = "linux", Darwin = "darwin" })[os_name]
  if not os_key then
    error("unsupported remote OS " .. tostring(os_name) .. " (need Linux or Darwin)")
  end
  local arch_key = ({
    x86_64 = "x86_64",
    amd64 = "x86_64",
    aarch64 = "aarch64",
    arm64 = "aarch64",
  })[machine]
  if not arch_key then
    error("unsupported remote arch " .. tostring(machine) .. " (need x86_64 or aarch64)")
  end
  return os_key .. "-" .. arch_key
end

-- Substitute `{platform}` in a release-URL template.
function M.release_url(template, platform)
  return (template:gsub("{platform}", platform))
end

-- Run `argv` on the LOCAL machine and resolve `{ code, stdout, stderr }`. A thin wrapper so
-- every provisioning step reads uniformly (and tests can see one seam).
local function run(argv)
  return btv.run_local({ cmd = argv })
end
M._run = run

-- Resolve the bemtvi command to launch on the remote, per `opts.binary`:
--   * `"path"` (default) — assume `opts.remote_bemtvi` (e.g. `"bemtvi"`) is on the remote PATH.
--   * `"install"` — reuse an already-installed copy at `install_dir/bemtvi-<platform>`, else
--     fetch the matching release binary to a LOCAL cache (`btv.http.fetch_local`), copy it in
--     (`backend.copy_argv`), and `chmod +x`. Returns the remote path.
-- Returns a promise of the remote command string. Every failure is loud (a bad download, a
-- failed copy) — the connector must not swap onto a daemon it couldn't stage.
function M.ensure_binary(backend, target, os_name, machine, opts)
  return btv.async(function()
    if opts.binary ~= "install" then
      return opts.remote_bemtvi
    end
    local platform = M.platform(os_name, machine)
    local remote_path = opts.install_dir .. "/bemtvi-" .. platform
    -- Already staged on the remote? Reuse it (executability is the test).
    local have = btv.await(run(backend.exec_argv(target, { "test", "-x", remote_path })))
    if have.code == 0 then
      return remote_path
    end
    progress("installing bemtvi (" .. platform .. ") on " .. target.display .. "…")
    -- Fetch to the local cache once (keyed by platform), then reuse across connects.
    local cache = opts.cache_dir .. "/bemtvi-" .. platform
    if not btv.await(btv.fs_local.exists(cache)) then
      local url = M.release_url(opts.release_url, platform)
      progress("downloading " .. url)
      local res = btv.await(btv.http.fetch_local(url))
      if not res.ok then
        error("download failed: HTTP " .. res.status .. " for " .. url)
      end
      btv.await(btv.fs_local.mkdir(opts.cache_dir, { recursive = true }))
      btv.await(btv.fs_local.write(cache, res.body))
    end
    -- Stage it on the remote: ensure the dir, copy the binary in, make it executable.
    btv.await(run(backend.exec_argv(target, { "mkdir", "-p", opts.install_dir })))
    local cp = btv.await(run(backend.copy_argv(target, cache, remote_path)))
    if cp.code ~= 0 then
      error("copying bemtvi to " .. target.display .. " failed: " .. trim(cp.stderr))
    end
    btv.await(run(backend.exec_argv(target, { "chmod", "+x", remote_path })))
    return remote_path
  end)()
end

-- Resolve `url` through `backend` into a `btv.session.reconnect` spec (§C). Detects the
-- remote's platform (which doubles as a reachability check), resolves the bemtvi command, and
-- builds the spawn transport. Returns a promise of the spec; `btv.connect` awaits it and swaps
-- the window. Fails LOUD (an unreachable host, an unsupported platform) rather than swapping
-- onto nothing.
function M.resolve(backend, url, opts)
  return btv.async(function()
    local target = backend.parse(url)
    progress("connecting to " .. target.display .. "…")
    if backend.prepare then
      btv.await(backend.prepare(target))
    end
    -- Reachability + platform: `uname -sm` on the remote. A non-zero exit / empty output is a
    -- failed connect (the daemon would never come up), surfaced with the tool's own stderr.
    local u = btv.await(run(backend.exec_argv(target, { "uname", "-sm" })))
    if u.code ~= 0 then
      local why = trim(u.stderr)
      error(
        "could not reach "
          .. url
          .. (why ~= "" and (" — " .. why) or (" (exit " .. u.code .. ")"))
      )
    end
    local os_name, machine = trim(u.stdout):match("^(%S+)%s+(%S+)")
    if not os_name then
      error("unexpected `uname -sm` from " .. url .. ": " .. trim(u.stdout))
    end
    progress(target.display .. " is " .. os_name .. " " .. machine)
    local remote_bemtvi = btv.await(M.ensure_binary(backend, target, os_name, machine, opts))
    return {
      transport = { kind = "spawn", argv = backend.spawn_argv(target, remote_bemtvi) },
      config_source = opts.config_source,
    }
  end)()
end

return M
