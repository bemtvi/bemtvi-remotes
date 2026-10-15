# bemtvi-remotes

A connector for [bemtvi](https://github.com/bemtvi/bemtvi)'s `:connect`, in the VS Code
Remote model. It teaches `:connect` two URL schemes and reloads the window onto the
remote's `bemtvi --daemon`. The editor (buffers, Lua, keystrokes) stays local; only the
filesystem, process and LSP seams cross the wire.

```
:connect container://<name>        a running Docker container (docker exec)
:connect ssh://[user@]host[:port]  a remote host over ssh (multiplexed)
:RemotesClean                      close any lingering ssh control-masters
```

## Install

Install it as a system plugin, so it is re-seeded into every session, including the one
`:connect` swaps you onto:

```lua
btv.plugins.system({ "bemtvi/bemtvi-remotes" })
```

The defaults work without a `setup()` call. Options, the provisioning flow and the Lua
API are documented in [`doc/bemtvi-remotes.md`](doc/bemtvi-remotes.md), also available
in the editor as `:help bemtvi-remotes`.

## License

MIT © 2026 David Rios
