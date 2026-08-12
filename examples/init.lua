-- ~~~ bemtvi-remotes: connect the editor to a container / host ~~~
--
-- This connector teaches `:connect` two schemes and reloads the window onto the remote's
-- `bemtvi --daemon` — the editor (buffers, Lua, keystrokes) stays local; only the
-- fs/process/LSP seams cross the wire.
--
--     :connect container://<name>        -- a running Docker container (docker exec)
--     :connect ssh://[user@]host[:port]  -- a remote host over ssh (multiplexed)
--
-- Install it as a SYSTEM plugin so it is present before any `:connect` and survives the
-- reload onto the remote (the client re-seeds the system tier into every session):
--
--     :lua btv.plugins.system{ "bemtvi/bemtvi-remotes" }
--
-- (or clone it into `stdpath("data")/system/bemtvi-remotes` yourself). Then
-- `require("bemtvi-remotes").setup{...}` — as below — tunes it. As an ordinary
-- (non-system) plugin it still works in the local session; it just won't persist across a
-- swap onto a *different* remote.
--
-- Try it against a real container:
--
--     docker run -d --name devbox -w /root alpine sleep infinity   # a throwaway box
--     # ensure an bemtvi daemon binary is reachable inside it (binary = "install" can stage
--     # it for you from a release URL; or bake bemtvi into your image), then:
--     :connect container://devbox
--     :lua print(btv.daemon.status())     -- "connected": you're editing IN the container

require("bemtvi-remotes").setup({
  -- How to obtain bemtvi on the remote:
  --   "path"    — assume `remote_bemtvi` (below) is already on the remote PATH (default).
  --   "install" — reuse install_dir/bemtvi-<platform>, else fetch the matching release binary
  --               (release_url) to a local cache and copy it in (docker cp / scp), chmod +x.
  binary = "path",
  remote_bemtvi = "bemtvi",

  -- binary = "install" knobs (unused for "path"):
  -- install_dir = "/tmp/bemtvi-remote",
  -- release_url = "https://github.com/davidrios/bemtvi/releases/latest/download/bemtvi-{platform}",

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
-- the bemtvi repo for the full statusline segment).
btv.autocmd.create("User", {
  pattern = "DaemonStatusChanged",
  callback = function()
    local phase = btv.daemon.status()
    if phase and phase ~= "local" then
      btv.notify("daemon: " .. phase)
    end
  end,
})
