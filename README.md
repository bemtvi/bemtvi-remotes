# bemtvi-remotes

A **connector** for [bemtvi](https://github.com/bemtvi/bemtvi)'s `:connect` — the VS Code
Remote model, built entirely on the native `btv.connect` / `btv.session.reconnect` plugin API
(ADR 0002): no core changes. It teaches `:connect` two URL schemes and **reloads the window
onto the remote's `bemtvi --daemon`**. The editor — buffers, Lua, the keystroke path — stays
local; only the filesystem / process / LSP **seams** cross the wire, so editing stays
zero-round-trip while your files, tools, and language servers live on the remote.

```
:connect container://<name>        connect to a running Docker container (docker exec)
:connect ssh://[user@]host[:port]  connect to a remote host over ssh (multiplexed)
:RemotesClean             close any lingering ssh control-masters
```

## Install

This is a **connector**, so it works best as a **system plugin** — the bemtvi client re-seeds
the system tier into *every* session, including the one it swaps you onto, which is what
keeps `:connect` available after the reload:

```lua
:lua btv.plugins.system{ "bemtvi/bemtvi-remotes" }
```

That clones it into `stdpath("data")/system/` and loads it. (You can also clone it there
yourself.) It also works as an ordinary plugin in the local session — it just won't persist
across a swap onto a *different* remote.

Then tune it (optional — the defaults work):

```lua
require("bemtvi-remotes").setup({
  binary = "path",              -- "path" (assume bemtvi on the remote PATH) | "install"
  remote_bemtvi = "bemtvi",       -- the bemtvi command on the remote (binary = "path")
  config_source = "remote",     -- "remote" (the remote's config) | "local" (yours; remote seams only)
  control_persist = "60",       -- ssh control-master idle lifetime, seconds
})
```

## How it works

On `:connect <url>`, bemtvi routes the URL through the local VM's connect registry; this
plugin's resolver runs **on your machine** (the side that dials the daemon) over the
[local-always seam](https://github.com/bemtvi/bemtvi) — `btv.run_local` / `btv.fs_local` /
`btv.http.fetch_local` — so provisioning happens locally even when you invoke it from inside
an existing remote session. It then:

1. **Detects the remote's platform** — `docker exec <c> uname -sm` / `ssh <host> uname -sm`
   (which doubles as a reachability check; an unreachable target fails loud, no half-swap).
2. **Resolves the bemtvi daemon command** on the remote:
   - `binary = "path"` (default) — assume `bemtvi` is on the remote PATH.
   - `binary = "install"` — reuse `install_dir/bemtvi-<platform>` if present, else fetch the
     matching release binary to a local cache (`btv.http.fetch_local`), copy it in
     (`docker cp` / `scp`), and `chmod +x`.
3. **Returns a spawn transport** (`docker exec -i … bemtvi --daemon` / `ssh … bemtvi --daemon`,
   structured argv — no shell), and bemtvi reloads the window onto it.

For `ssh://`, connections are **multiplexed**: a control-master (`ControlMaster=auto` + a
per-host `ControlPath`) is created by the first call and reused by the daemon spawn and every
reconnect, so a dropped link re-dials without re-authenticating. `ControlPersist` bounds its
idle lifetime; `:RemotesClean` (keyed by on-disk sidecars, so it survives a swap)
closes masters explicitly.

### `config_source` (local vs remote config)

`config_source = "remote"` (default) runs the remote's own config + plugins after the swap.
`config_source = "local"` keeps **your** editor config (keymaps, colors, options) and lets the
container back only the fs/process/LSP seams — the classic dev-container shape: your editor,
the container's toolchain.

## Options

| option            | default                                   | meaning                                                             |
| ----------------- | ----------------------------------------- | ------------------------------------------------------------------- |
| `binary`          | `"path"`                                  | `"path"` (bemtvi on the remote PATH) or `"install"` (fetch + stage)  |
| `remote_bemtvi`    | `"bemtvi"`                                 | the bemtvi command on the remote (`binary = "path"`)                 |
| `install_dir`     | `"/tmp/bemtvi-remote"`                      | where `binary = "install"` stages the binary on the remote          |
| `release_url`     | `…/releases/latest/download/bemtvi-{platform}` | release-URL template; `{platform}` → e.g. `linux-x86_64`         |
| `cache_dir`       | `stdpath("cache")/bemtvi-remotes`| local download cache                                                |
| `config_source`   | `"remote"`                                | `"remote"` or `"local"` (see above)                                 |
| `control_persist` | `"60"`                                    | ssh control-master idle lifetime (seconds, or `"yes"`)              |
| `docker`/`ssh`/`scp` | `"docker"`/`"ssh"`/`"scp"`              | the CLIs to invoke (override to point at a wrapper)                 |

## Testing

Pure-Lua, hermetic (no Docker, no network, no host — fake `docker`/`ssh` scripts stand in):

```
bemtvi --test-plugin .
```

## License

MIT © 2026 David Rios
