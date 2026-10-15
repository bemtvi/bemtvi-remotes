-- The full provisioning flow (arch detect -> resolve bemtvi -> build the swap spec), driven
-- against a **fake** `docker` — a real /bin/sh script that answers `uname` with a chosen
-- platform and exits 0 for everything else. Hermetic: no Docker, no network, no host. The
-- daemon is never actually spawned; the argv the connector *builds* is what's asserted. Run
-- with `bemtvi --test-plugin .`.

local backends = require("bemtvi-remotes.backends")
local provision = require("bemtvi-remotes.provision")

-- Write a fake `docker` into a fresh temp dir and return its path. `uname` is the platform
-- string `docker exec <c> uname -sm` prints; `reachable = false` makes that call exit 1.
-- `installed` controls whether `docker exec <c> test -x <path>` succeeds (binary = "install"
-- reuse path) or fails (would trigger a download — not exercised here).
local function make_fake_docker(uname, reachable, installed)
  return btv.async(function()
    local dir = btv.stdpath("cache") .. "/bemtvi-remotes-test/" .. btv.uuid()
    btv.await(btv.fs_local.mkdir(dir, { recursive = true }))
    local uname_branch = reachable and ('echo "' .. uname .. '"') or "exit 1"
    local test_branch = installed and "exit 0" or "exit 1"
    local body = table.concat({
      "#!/bin/sh",
      'if [ "$1" = "exec" ]; then',
      "  shift; shift",
      '  case "$1" in',
      "    uname) " .. uname_branch .. " ;;",
      "    test) " .. test_branch .. " ;;",
      "    *) exit 0 ;;",
      "  esac",
      "fi",
      "exit 0",
      "",
    }, "\n")
    local path = dir .. "/docker"
    btv.await(btv.fs_local.write(path, body))
    btv.await(btv.run_local({ cmd = { "chmod", "+x", path } }))
    return path
  end)()
end

btv.test.describe("resolve (docker, binary = path)", function()
  btv.test.it("detects the platform and builds the daemon spawn spec", function()
    local docker = btv.await(make_fake_docker("Linux x86_64", true, false))
    local opts =
      { docker = docker, remote_bemtvi = "bemtvi", binary = "path", config_source = "remote" }
    local spec = btv.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    btv.test.expect(spec.transport.kind).to_be("spawn")
    btv.test.expect(spec.transport.argv).to_equal({
      docker,
      "exec",
      "-i",
      "devbox",
      "bemtvi",
      "--daemon",
    })
    btv.test.expect(spec.config_source).to_be("remote")
  end)

  btv.test.it("honors config_source = local (the dev-container shape)", function()
    local docker = btv.await(make_fake_docker("Linux x86_64", true, false))
    local opts =
      { docker = docker, remote_bemtvi = "bemtvi", binary = "path", config_source = "local" }
    local spec = btv.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    btv.test.expect(spec.config_source).to_be("local")
  end)

  btv.test.it("fails loud when the container is unreachable", function()
    local docker = btv.await(make_fake_docker("Linux x86_64", false, false))
    local opts = { docker = docker, remote_bemtvi = "bemtvi", binary = "path" }
    local ok, err = pcall(function()
      btv.await(provision.resolve(backends.docker(opts), "container://ghost", opts))
    end)
    btv.test.expect(ok).to_be(false)
    btv.test.expect(tostring(err)).to_contain("could not reach")
  end)
end)

btv.test.describe("resolve (docker, binary = install)", function()
  btv.test.it("reuses an already-installed binary at install_dir/bemtvi-<platform>", function()
    -- `test -x` succeeds -> no download/copy; the spawn uses the staged path.
    local docker = btv.await(make_fake_docker("Linux x86_64", true, true))
    local opts = {
      docker = docker,
      binary = "install",
      install_dir = "/opt/bemtvi",
      config_source = "remote",
    }
    local spec = btv.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    btv.test.expect(spec.transport.argv).to_equal({
      docker,
      "exec",
      "-i",
      "devbox",
      "/opt/bemtvi/bemtvi-linux-x86_64",
      "--daemon",
    })
  end)
end)
