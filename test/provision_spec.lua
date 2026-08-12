-- The provisioning engine's pure helpers: platform mapping (uname -> release key) and the
-- release-URL template. Run with `bemtvi --test-plugin .`.

local provision = require("bemtvi-remotes.provision")

btv.test.describe("platform mapping", function()
  btv.test.it("maps Linux x86_64 -> linux-x86_64", function()
    btv.test.expect(provision.platform("Linux", "x86_64")).to_be("linux-x86_64")
  end)

  btv.test.it("maps Darwin arm64 -> darwin-aarch64 (arch aliases fold)", function()
    btv.test.expect(provision.platform("Darwin", "arm64")).to_be("darwin-aarch64")
    btv.test.expect(provision.platform("Linux", "amd64")).to_be("linux-x86_64")
  end)

  btv.test.it("fails loud on an OS/arch with no published binary", function()
    btv.test.expect(pcall(provision.platform, "Plan9", "x86_64")).to_be(false)
    btv.test.expect(pcall(provision.platform, "Linux", "riscv64")).to_be(false)
  end)
end)

btv.test.describe("release URL template", function()
  btv.test.it("substitutes {platform}", function()
    local url = provision.release_url("https://host/dl/bemtvi-{platform}", "linux-aarch64")
    btv.test.expect(url).to_be("https://host/dl/bemtvi-linux-aarch64")
  end)
end)
