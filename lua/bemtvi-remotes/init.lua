-- bemtvi-remotes — a *connector* for bemtvi's `:connect` (the VS Code Remote model,
-- ADR 0002 / the native `btv.connect` API). It teaches `:connect` two schemes:
--
--   :connect container://<name>       -- a running Docker container (docker exec)
--   :connect ssh://[user@]host[:port] -- a remote host over ssh (multiplexed)
--
-- On invoke it provisions the target FROM THIS MACHINE (the local-always seam:
-- `btv.run_local` / `btv.fs_local` / `btv.http.fetch_local`) — detects the remote's arch/OS,
-- ensures the bemtvi daemon is there (assume it's on the PATH, or fetch + install the matching
-- release binary), and returns a spawn transport. bemtvi then reloads the window onto the
-- remote daemon: the editor (buffers, Lua, keystrokes) stays local; only the fs/process/LSP
-- seams cross the wire.
--
-- It is a **system plugin** (installed under `stdpath("data")/system/`, or promoted with
-- `btv.plugins.system{...}`), so the client re-seeds it into every session — including the
-- one it swaps you onto — which is what keeps `:connect` available after the reload.

local backends = require("bemtvi-remotes.backends")
local provision = require("bemtvi-remotes.provision")

local M = {}

-- Defaults. Every field is overridable via `require("bemtvi-remotes").setup{...}`.
local DEFAULTS = {
  docker = "docker", -- the docker CLI
  ssh = "ssh", -- the ssh CLI
  scp = "scp", -- the scp CLI (used only by binary = "install")
  remote_bemtvi = "bemtvi", -- the bemtvi command on the remote (binary = "path")
  binary = "path", -- "path" (assume bemtvi on the remote PATH) | "install" (fetch + stage it)
  install_dir = "/tmp/bemtvi-remote", -- where binary = "install" stages the binary on the remote
  -- Release-URL template for binary = "install"; `{platform}` -> e.g. "linux-x86_64".
  release_url = "https://github.com/davidrios/bemtvi/releases/latest/download/bemtvi-{platform}",
  cache_dir = nil, -- local download cache (default stdpath("cache")/bemtvi-remotes)
  control_dir = nil, -- ssh control-socket dir (default cache_dir/cm)
  control_persist = "60", -- ssh ControlPersist (seconds, or "yes"): master idle-lifetime
  config_source = "remote", -- §D: run the remote's config ("remote") or this machine's ("local")
}

M._opts = M._opts or vim.tbl_extend("force", {}, DEFAULTS)

-- `setup(opts)` — merge `opts`, register the `container://` / `ssh://` connect providers, and
-- define `:RemotesClean`. Idempotent: re-registering a scheme is fine (a later
-- `btv.connect.register` wins), so calling `setup` again just re-applies options.
function M.setup(opts)
  M._opts = vim.tbl_extend("force", M._opts, opts or {})
  local cache = M._opts.cache_dir or (vim.fn.stdpath("cache") .. "/bemtvi-remotes")
  M._opts.cache_dir = cache
  M._opts.control_dir = M._opts.control_dir or (cache .. "/cm")

  -- A resolver closes over the live `M._opts` (read at connect time, so a later `setup` is
  -- honored) and hands a fresh backend to the shared engine.
  btv.connect.register("container", function(url)
    return provision.resolve(backends.docker(M._opts), url, M._opts)
  end)
  btv.connect.register("ssh", function(url)
    return provision.resolve(backends.ssh(M._opts), url, M._opts)
  end)

  btv.command("RemotesClean", function()
    M.clean()
  end, {
    desc = "Close any lingering ssh control-masters opened by :connect ssh://…",
  })
end

-- `disconnect(url)` — tear down the ssh control-master for `url` (`ssh -O exit`). Best-effort:
-- a master that already expired (ControlPersist) just reports "no such control connection",
-- which is fine. A no-op for `container://` (docker exec leaves no side process).
function M.disconnect(url)
  return btv.async(function()
    if not url:match("^ssh://") then
      return
    end
    local backend = backends.ssh(M._opts)
    local target = backend.parse(url)
    btv.await(btv.run_local({ cmd = backend.teardown_argv(target) }))
    -- Drop the socket + sidecar so a later :RemotesClean doesn't retry it.
    btv.await(btv.fs_local.remove(backend.control_path(target)))
    btv.await(btv.fs_local.remove(backend.control_path(target) .. ".host"))
  end)()
end

-- `clean()` — close every ssh control-master this plugin opened, keyed by the on-disk
-- `<hash>.host` sidecars (which survive a session swap, unlike Lua state). For each: read the
-- destination, `ssh -O exit` it via its socket, then remove the socket + sidecar. Idempotent
-- and safe to call from any session.
function M.clean()
  return btv.async(function()
    local dir = M._opts.control_dir
    if not btv.await(btv.fs_local.exists(dir)) then
      return provision._progress("no ssh control-masters to close")
    end
    local entries = btv.await(btv.fs_local.readdir(dir))
    local closed = 0
    for _, e in ipairs(entries) do
      local hash = e.name:match("^(.+)%.host$")
      if hash then
        local socket = dir .. "/" .. hash
        local dest = (btv.await(btv.fs_local.read_text(dir .. "/" .. e.name))):match("^%s*(.-)%s*$")
        btv.await(btv.run_local({
          cmd = { M._opts.ssh, "-o", "ControlPath=" .. socket, "-O", "exit", dest },
        }))
        btv.await(btv.fs_local.remove(socket))
        btv.await(btv.fs_local.remove(dir .. "/" .. e.name))
        closed = closed + 1
      end
    end
    provision._progress(
      closed == 0 and "no ssh control-masters to close"
        or ("closed " .. closed .. " ssh control-master(s)")
    )
  end)()
end

return M
