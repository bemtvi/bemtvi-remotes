-- Auto-loaded when the plugin is on the runtimepath (sourced from `plugin/` like a neovim
-- plugin). Registers the `container://` / `ssh://` connect providers with defaults so
-- `:connect` works out of the box; `setup()` is idempotent, so a user calling
-- `require("bemtvi-remotes").setup{...}` with their own options is harmless.
--
-- As a *connector* this plugin is meant to be a SYSTEM plugin (under
-- `stdpath("data")/system/`), so it is present before any `:connect` and survives the reload
-- onto the remote. It also works as an ordinary plugin in the local session.
require("bemtvi-remotes").setup()
