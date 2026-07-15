-- The provisioning engine's pure helpers: platform mapping (uname -> release key) and the
-- release-URL template. Run with `nxvim --test-plugin .`.

local provision = require("nxvim-remote-containers.provision")

nx.test.describe("platform mapping", function()
  nx.test.it("maps Linux x86_64 -> linux-x86_64", function()
    nx.test.expect(provision.platform("Linux", "x86_64")).to_be("linux-x86_64")
  end)

  nx.test.it("maps Darwin arm64 -> darwin-aarch64 (arch aliases fold)", function()
    nx.test.expect(provision.platform("Darwin", "arm64")).to_be("darwin-aarch64")
    nx.test.expect(provision.platform("Linux", "amd64")).to_be("linux-x86_64")
  end)

  nx.test.it("fails loud on an OS/arch with no published binary", function()
    nx.test.expect(pcall(provision.platform, "Plan9", "x86_64")).to_be(false)
    nx.test.expect(pcall(provision.platform, "Linux", "riscv64")).to_be(false)
  end)
end)

nx.test.describe("release URL template", function()
  nx.test.it("substitutes {platform}", function()
    local url = provision.release_url("https://host/dl/nxvim-{platform}", "linux-aarch64")
    nx.test.expect(url).to_be("https://host/dl/nxvim-linux-aarch64")
  end)
end)
