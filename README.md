# nxvim-remote-containers

A **connector** for [nxvim](https://github.com/davidrios/nxvim)'s `:connect` — the VS Code
Remote model, built entirely on the native `nx.connect` / `nx.session.reconnect` plugin API
(ADR 0002): no core changes. It teaches `:connect` two URL schemes and **reloads the window
onto the remote's `nxvim --daemon`**. The editor — buffers, Lua, the keystroke path — stays
local; only the filesystem / process / LSP **seams** cross the wire, so editing stays
zero-round-trip while your files, tools, and language servers live on the remote.

```
:connect container://<name>        connect to a running Docker container (docker exec)
:connect ssh://[user@]host[:port]  connect to a remote host over ssh (multiplexed)
:RemoteContainersClean             close any lingering ssh control-masters
```

## Install

This is a **connector**, so it works best as a **system plugin** — the nxvim client re-seeds
the system tier into *every* session, including the one it swaps you onto, which is what
keeps `:connect` available after the reload:

```lua
:lua nx.plugins.system{ "nxvim/nxvim-remote-containers" }
```

That clones it into `stdpath("data")/system/` and loads it. (You can also clone it there
yourself.) It also works as an ordinary plugin in the local session — it just won't persist
across a swap onto a *different* remote.

Then tune it (optional — the defaults work):

```lua
require("nxvim-remote-containers").setup({
  binary = "path",              -- "path" (assume nxvim on the remote PATH) | "install"
  remote_nxvim = "nxvim",       -- the nxvim command on the remote (binary = "path")
  config_source = "remote",     -- "remote" (the remote's config) | "local" (yours; remote seams only)
  control_persist = "60",       -- ssh control-master idle lifetime, seconds
})
```

## How it works

On `:connect <url>`, nxvim routes the URL through the local VM's connect registry; this
plugin's resolver runs **on your machine** (the side that dials the daemon) over the
[local-always seam](https://github.com/davidrios/nxvim) — `nx.run_local` / `nx.fs_local` /
`nx.http.fetch_local` — so provisioning happens locally even when you invoke it from inside
an existing remote session. It then:

1. **Detects the remote's platform** — `docker exec <c> uname -sm` / `ssh <host> uname -sm`
   (which doubles as a reachability check; an unreachable target fails loud, no half-swap).
2. **Resolves the nxvim daemon command** on the remote:
   - `binary = "path"` (default) — assume `nxvim` is on the remote PATH.
   - `binary = "install"` — reuse `install_dir/nxvim-<platform>` if present, else fetch the
     matching release binary to a local cache (`nx.http.fetch_local`), copy it in
     (`docker cp` / `scp`), and `chmod +x`.
3. **Returns a spawn transport** (`docker exec -i … nxvim --daemon` / `ssh … nxvim --daemon`,
   structured argv — no shell), and nxvim reloads the window onto it.

For `ssh://`, connections are **multiplexed**: a control-master (`ControlMaster=auto` + a
per-host `ControlPath`) is created by the first call and reused by the daemon spawn and every
reconnect, so a dropped link re-dials without re-authenticating. `ControlPersist` bounds its
idle lifetime; `:RemoteContainersClean` (keyed by on-disk sidecars, so it survives a swap)
closes masters explicitly.

### `config_source` (local vs remote config)

`config_source = "remote"` (default) runs the remote's own config + plugins after the swap.
`config_source = "local"` keeps **your** editor config (keymaps, colors, options) and lets the
container back only the fs/process/LSP seams — the classic dev-container shape: your editor,
the container's toolchain.

## Options

| option            | default                                   | meaning                                                             |
| ----------------- | ----------------------------------------- | ------------------------------------------------------------------- |
| `binary`          | `"path"`                                  | `"path"` (nxvim on the remote PATH) or `"install"` (fetch + stage)  |
| `remote_nxvim`    | `"nxvim"`                                 | the nxvim command on the remote (`binary = "path"`)                 |
| `install_dir`     | `"/tmp/nxvim-remote"`                      | where `binary = "install"` stages the binary on the remote          |
| `release_url`     | `…/releases/latest/download/nxvim-{platform}` | release-URL template; `{platform}` → e.g. `linux-x86_64`         |
| `cache_dir`       | `stdpath("cache")/nxvim-remote-containers`| local download cache                                                |
| `config_source`   | `"remote"`                                | `"remote"` or `"local"` (see above)                                 |
| `control_persist` | `"60"`                                    | ssh control-master idle lifetime (seconds, or `"yes"`)              |
| `docker`/`ssh`/`scp` | `"docker"`/`"ssh"`/`"scp"`              | the CLIs to invoke (override to point at a wrapper)                 |

## Testing

Pure-Lua, hermetic (no Docker, no network, no host — fake `docker`/`ssh` scripts stand in):

```
nxvim --test-plugin .
```

## License

MIT © 2026 David Rios
