<!-- DO NOT EDIT doc/bemtvi-remotes.txt BY HAND. It is generated from this file by
panvimdoc — run `scripts/gen-vimdoc.sh` after editing. -->

A connector for bemtvi's `:connect`, in the VS Code Remote model. It teaches `:connect` two URL
schemes and reloads the window onto the remote's `bemtvi --daemon`. The editor (buffers, Lua,
the keystroke path) stays local; only the filesystem, process and LSP seams cross the wire, so
editing stays zero-round-trip while your files, tools and language servers live on the remote.

It is built entirely on the native `btv.connect` / `btv.session.reconnect` plugin API (ADR 0002),
with no core changes.

<!-- Passed through verbatim so `:help bemtvi-remotes` lands on this page
     (panvimdoc derives per-section tags but no bare project tag). -->
```vimdoc
                                                                *bemtvi-remotes*
```

# Install

This plugin is a connector, so it works best as a system plugin. The bemtvi client re-seeds the
system tier into every session, including the one `:connect` swaps you onto, which is what keeps
`:connect` available after the reload:

```lua
btv.plugins.system({ "bemtvi/bemtvi-remotes" })
```

That clones it into `stdpath("data")/system/` and loads it. You can also clone it there yourself.

It also works as an ordinary plugin in the local session; it just won't persist across a swap
onto a different remote.

The plugin's `plugin/bemtvi-remotes.lua` calls `setup()` with the defaults when it loads, so
`:connect` works without any configuration. Call `setup()` yourself only to change options.

# Commands

## :connect

`:connect` itself belongs to bemtvi. This plugin registers resolvers for two schemes:

```
:connect container://<name>        a running Docker container
:connect ssh://[user@]host[:port]  a remote host over ssh
```

For `container://`, everything after the scheme is the container name or id. For `ssh://`, the
user and port are optional. A container name, ssh host or ssh user that begins with `-` is
rejected, since it would reach `docker` or `ssh` as an option.

## :RemotesClean

Closes every ssh control-master this plugin opened (`ssh -O exit`) and removes their sockets.
It finds them through `<hash>.host` sidecar files in `control_dir`, which survive a session swap,
so it works from any session. Reports how many it closed, or that there were none.

# Configuration

```lua
require("bemtvi-remotes").setup({
  binary = "path",          -- "path" | "install"
  remote_bemtvi = "bemtvi", -- bemtvi on the remote PATH
  config_source = "remote", -- "remote" | "local"
  control_persist = "60",   -- ssh master idle lifetime
})
```

`setup()` merges the table over the current options, so each call only changes the keys it
names. Resolvers read the options at connect time, so a later `setup()` takes effect on the next
`:connect`.

## Options

- `binary` (default `"path"`): how to obtain bemtvi on the remote.
  `"path"` assumes `remote_bemtvi` is on the remote `PATH`. `"install"`
  fetches and stages the matching release binary (see `install_dir`).
- `remote_bemtvi` (default `"bemtvi"`): the bemtvi command run on the
  remote when `binary = "path"`.
- `install_dir` (default `"/tmp/bemtvi-remote"`): where
  `binary = "install"` stages the binary on the remote, as
  `bemtvi-<platform>`.
- `release_url`: the release-URL template for `binary = "install"`.
  `{platform}` is replaced with the platform key, such as
  `linux-x86_64` or `darwin-aarch64`. The default is
  `https://github.com/bemtvi/bemtvi/releases/latest/download/bemtvi-{platform}`.
- `cache_dir` (default `stdpath("cache")/bemtvi-remotes`): the local
  cache for downloaded release binaries.
- `control_dir` (default `<cache_dir>/cm`): the local directory for ssh
  control sockets and their `.host` sidecars.
- `control_persist` (default `"60"`): the ssh `ControlPersist` value,
  the seconds a control-master stays alive after its last connection,
  or `"yes"` to keep it until it is closed.
- `config_source` (default `"remote"`): `"remote"` runs the remote's
  own config and plugins after the swap. `"local"` keeps your editor
  config (keymaps, colors, options) and lets the remote back only the
  fs, process and LSP seams.
- `docker` (default `"docker"`): the docker CLI. Override it to point
  at a wrapper.
- `ssh` (default `"ssh"`): the ssh CLI.
- `scp` (default `"scp"`): the scp CLI, used only by
  `binary = "install"` over ssh.

## config_source

`config_source = "local"` is the classic dev-container shape: your editor, the container's
toolchain. With `"remote"`, the session after the swap behaves as if bemtvi had been started on
the remote.

# How it works

On `:connect <url>`, bemtvi routes the URL through the local VM's connect registry. This plugin's
resolver runs on your machine (the side that dials the daemon) over the local-always seam
(`btv.run_local`, `btv.fs_local`, `btv.http.fetch_local`), so provisioning happens locally even
when you run `:connect` from inside an existing remote session. It then:

1. Detects the remote's platform with `docker exec <c> uname -sm` or
   `ssh <host> uname -sm`. This doubles as a reachability check: an
   unreachable target fails loud, with no half-swap. Only Linux and
   Darwin on x86_64 or aarch64 are supported.
2. Resolves the bemtvi daemon command on the remote. With
   `binary = "path"` it is `remote_bemtvi` as is. With
   `binary = "install"`, an already-executable
   `install_dir/bemtvi-<platform>` is reused. Otherwise the release
   binary is downloaded to `cache_dir` (once per platform) with
   `btv.http.fetch_local`, `install_dir` is created, the binary is
   copied in with `docker cp` or `scp`, and `chmod +x` is run on it. A
   failed download or copy fails loud.
3. Returns a spawn transport (`docker exec -i <c> <bemtvi> --daemon` or
   `ssh … <host> <bemtvi> --daemon`) as structured argv with no shell,
   and bemtvi reloads the window onto it.

Progress is reported on the message line, prefixed with `remotes:`.

## ssh multiplexing

`ssh://` connections are multiplexed. A control-master (`ControlMaster=auto` and a per-host
`ControlPath` under `control_dir`) is created by the first ssh call and reused by the daemon
spawn, every reconnect, and `scp`. A dropped link re-dials without re-authenticating.
`control_persist` bounds the master's idle lifetime, after which it exits on its own;
`:RemotesClean` closes masters explicitly.

# Lua API

## setup()

`require("bemtvi-remotes").setup(opts)` merges `opts` into the options, registers the
`container` and `ssh` connect resolvers, and defines `:RemotesClean`. It is idempotent: calling
it again re-registers the same resolvers and re-applies the options.

## clean()

`require("bemtvi-remotes").clean()` does what `:RemotesClean` does and returns a promise that
settles when every master has been closed.

## disconnect()

`require("bemtvi-remotes").disconnect(url)` closes the ssh control-master for one `ssh://` URL
(`ssh -O exit`) and removes its socket and sidecar. It returns a promise. For any other URL,
including `container://`, it does nothing, since `docker exec` leaves no side process.

# Testing

The specs are pure Lua and hermetic: fake `docker` and `ssh` scripts stand in, so no Docker,
network or remote host is needed. From the repository root:

```sh
bemtvi --test-plugin .
```

`examples/init.lua` is a commented configuration to try against a real container.
