-- Backend descriptors: how to run a command on a remote, spawn the daemon there, and copy a
-- file in — one per transport (docker `exec`, ssh). The provisioning engine
-- (provision.lua) is backend-agnostic; each factory below closes over `opts` and returns the
-- four (+ optional `prepare`) closures it calls. Everything is structured argv (no shell), so
-- a container/host name can't smuggle shell metacharacters.

local M = {}

-- ----- docker (container://<name>) -------------------------------------------

-- `container://<name-or-id>` -> the container reference. The whole authority+path is the
-- container name/id (no user/port), so take everything after the scheme, trimmed.
local function parse_container(url)
  local name = url:match("^container://(.+)$")
  name = name and name:match("^%s*(.-)%s*$")
  if not name or name == "" then
    error(
      "remotes: malformed container URL " .. tostring(url) .. " (want container://<name>)"
    )
  end
  if name:sub(1, 1) == "-" then
    error("remotes: container name must not begin with '-' (" .. name .. ")")
  end
  return { display = name, ref = name }
end

-- The docker backend. `docker exec` runs commands / the daemon inside the container;
-- `docker cp` stages a binary. No teardown (a `docker exec` leaves no side process).
function M.docker(opts)
  return {
    scheme = "container",
    parse = parse_container,
    exec_argv = function(target, cmd)
      local argv = { opts.docker, "exec", target.ref }
      for _, a in ipairs(cmd) do
        argv[#argv + 1] = a
      end
      return argv
    end,
    -- `-i` keeps stdin open: the daemon wire rides the container's stdin/stdout.
    spawn_argv = function(target, remote_bemtvi)
      return { opts.docker, "exec", "-i", target.ref, remote_bemtvi, "--daemon" }
    end,
    copy_argv = function(target, local_path, remote_path)
      return { opts.docker, "cp", local_path, target.ref .. ":" .. remote_path }
    end,
  }
end

-- ----- ssh (ssh://[user@]host[:port]) ----------------------------------------

-- Parse `ssh://[user@]host[:port]` into `{ dest = "[user@]host", port = <string|nil> }`.
-- Rejects a `user`/`host` beginning with `-` (it would be smuggled to ssh as an option — an
-- RCE vector), mirroring the core's built-in ssh-target hardening.
local function parse_ssh(url)
  local rest = url:match("^ssh://(.+)$")
  rest = rest and rest:match("^%s*(.-)%s*$")
  if not rest or rest == "" then
    error(
      "remotes: malformed ssh URL " .. tostring(url) .. " (want ssh://[user@]host[:port])"
    )
  end
  local user, hostport = rest:match("^([^@]+)@(.+)$")
  if not user then
    hostport = rest
  end
  local host, port = hostport:match("^(.-):(%d+)$")
  if not host then
    host = hostport
  end
  if host == "" then
    error("remotes: ssh URL has no host (" .. url .. ")")
  end
  if host:sub(1, 1) == "-" or (user and user:sub(1, 1) == "-") then
    error("remotes: ssh host/user must not begin with '-' (" .. url .. ")")
  end
  local dest = user and (user .. "@" .. host) or host
  return { display = dest .. (port and (":" .. port) or ""), dest = dest, port = port }
end

-- The ssh backend, with connection multiplexing: a control-master (`ControlMaster=auto` +
-- a per-host `ControlPath`) is auto-created by the first ssh call and reused by the daemon
-- spawn and every reconnect, so a dropped link re-dials without re-authenticating.
-- `ControlPersist` keeps the master alive briefly after the last connection and then it
-- self-expires — the automatic cleanup path. `M.disconnect` / `:RemotesClean`
-- (init.lua) tear a master down explicitly via `ssh -O exit`, keyed by the on-disk `.host`
-- sidecar so cleanup survives a VM swap.
function M.ssh(opts)
  -- A short, filesystem-safe control-socket path derived from the destination (unix socket
  -- paths are length-limited, so hash rather than embed the host). A sibling `.host` file
  -- records the destination so an explicit teardown can `ssh -O exit` it later.
  local function control_path(target)
    local key = btv.hash.sha256(target.dest .. "|" .. (target.port or "")):sub(1, 16)
    return opts.control_dir .. "/" .. key
  end

  local function base_args(target)
    local args = {}
    if target.port then
      args[#args + 1] = "-p"
      args[#args + 1] = target.port
    end
    -- The multiplexing options. `ControlPersist` is a string ("60" seconds, or "yes").
    local mux = {
      "-o",
      "ControlMaster=auto",
      "-o",
      "ControlPath=" .. control_path(target),
      "-o",
      "ControlPersist=" .. tostring(opts.control_persist),
    }
    for _, a in ipairs(mux) do
      args[#args + 1] = a
    end
    return args
  end

  return {
    scheme = "ssh",
    parse = parse_ssh,
    control_path = control_path,
    -- Ensure the control-socket dir exists and record the destination for teardown.
    prepare = function(target)
      return btv.async(function()
        btv.await(btv.fs_local.mkdir(opts.control_dir, { recursive = true }))
        btv.await(btv.fs_local.write(control_path(target) .. ".host", target.dest .. "\n"))
      end)()
    end,
    exec_argv = function(target, cmd)
      local argv = { opts.ssh }
      for _, a in ipairs(base_args(target)) do
        argv[#argv + 1] = a
      end
      argv[#argv + 1] = "--"
      argv[#argv + 1] = target.dest
      for _, a in ipairs(cmd) do
        argv[#argv + 1] = a
      end
      return argv
    end,
    spawn_argv = function(target, remote_bemtvi)
      local argv = { opts.ssh }
      for _, a in ipairs(base_args(target)) do
        argv[#argv + 1] = a
      end
      argv[#argv + 1] = "--"
      argv[#argv + 1] = target.dest
      argv[#argv + 1] = remote_bemtvi
      argv[#argv + 1] = "--daemon"
      return argv
    end,
    -- scp uses `-P` for the port (not ssh's `-p`) and shares the control socket.
    copy_argv = function(target, local_path, remote_path)
      local argv = { opts.scp, "-o", "ControlPath=" .. control_path(target) }
      if target.port then
        argv[#argv + 1] = "-P"
        argv[#argv + 1] = target.port
      end
      argv[#argv + 1] = local_path
      argv[#argv + 1] = target.dest .. ":" .. remote_path
      return argv
    end,
    -- `ssh -O exit` closes the multiplexed master for this destination.
    teardown_argv = function(target)
      return {
        opts.ssh,
        "-o",
        "ControlPath=" .. control_path(target),
        "-O",
        "exit",
        target.dest,
      }
    end,
  }
end

return M
