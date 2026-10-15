-- `setup(opts)`: merges over the defaults and derives the cache / control-socket dirs.
-- Run with `bemtvi --test-plugin .`.

local remotes = require("bemtvi-remotes")

btv.test.describe("setup", function()
  btv.test.it("merges opts over the defaults and derives cache_dir / control_dir", function()
    -- `M._opts` is module state the per-test baseline doesn't restore; put it back by hand.
    local saved = remotes._opts
    remotes._opts = btv.tbl.extend("force", {}, saved, { cache_dir = false, control_dir = false })
    local ok, err = pcall(function()
      remotes.setup({ control_persist = "yes", binary = "install" })
      local o = remotes._opts
      local cache = btv.stdpath("cache") .. "/bemtvi-remotes"
      btv.test.expect(o.control_persist).to_be("yes")
      btv.test.expect(o.binary).to_be("install")
      btv.test.expect(o.docker).to_be("docker")
      btv.test.expect(o.remote_bemtvi).to_be("bemtvi")
      btv.test.expect(o.cache_dir).to_be(cache)
      btv.test.expect(o.control_dir).to_be(cache .. "/cm")
    end)
    remotes._opts = saved
    if not ok then
      error(err, 0)
    end
  end)
end)
