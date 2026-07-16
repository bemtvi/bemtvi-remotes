-- ~~~ nxvim-remotes: connect the editor to a container / host ~~~
--
-- This connector teaches `:connect` two schemes and reloads the window onto the remote's
-- `nxvim --daemon` — the editor (buffers, Lua, keystrokes) stays local; only the
-- fs/process/LSP seams cross the wire.
--
--     :connect container://<name>        -- a running Docker container (docker exec)
--     :connect ssh://[user@]host[:port]  -- a remote host over ssh (multiplexed)
--
-- Install it as a SYSTEM plugin so it is present before any `:connect` and survives the
-- reload onto the remote (the client re-seeds the system tier into every session):
--
--     :lua nx.plugins.system{ "nxvim/nxvim-remotes" }
--
-- (or clone it into `stdpath("data")/system/nxvim-remotes` yourself). Then
-- `require("nxvim-remotes").setup{...}` — as below — tunes it. As an ordinary
-- (non-system) plugin it still works in the local session; it just won't persist across a
-- swap onto a *different* remote.
--
-- Try it against a real container:
--
--     docker run -d --name devbox -w /root alpine sleep infinity   # a throwaway box
--     # ensure an nxvim daemon binary is reachable inside it (binary = "install" can stage
--     # it for you from a release URL; or bake nxvim into your image), then:
--     :connect container://devbox
--     :lua print(nx.daemon.status())     -- "connected": you're editing IN the container

require("nxvim-remotes").setup({
  -- How to obtain nxvim on the remote:
  --   "path"    — assume `remote_nxvim` (below) is already on the remote PATH (default).
  --   "install" — reuse install_dir/nxvim-<platform>, else fetch the matching release binary
  --               (release_url) to a local cache and copy it in (docker cp / scp), chmod +x.
  binary = "path",
  remote_nxvim = "nxvim",

  -- binary = "install" knobs (unused for "path"):
  -- install_dir = "/tmp/nxvim-remote",
  -- release_url = "https://github.com/nxvim/nxvim/releases/latest/download/nxvim-{platform}",

  -- §D: run the remote's config after the swap ("remote", default), or keep THIS machine's
  -- editor config and let the container back only the fs/proc/LSP seams ("local" — the
  -- dev-container shape: your keymaps + colors, the container's toolchain).
  config_source = "remote",

  -- ssh multiplexing: keep the control-master alive this many seconds after the last
  -- connection so reconnects don't re-authenticate. `:RemotesClean` closes any
  -- lingering masters explicitly.
  control_persist = "60",
})

-- Surface the daemon link so you can SEE the swap took effect (see examples/daemon-status in
-- the nxvim repo for the full statusline segment).
nx.autocmd.create("User", {
  pattern = "DaemonStatusChanged",
  callback = function()
    local phase = nx.daemon.status()
    if phase and phase ~= "local" then
      nx.notify("daemon: " .. phase)
    end
  end,
})
