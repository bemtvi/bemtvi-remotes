-- The full provisioning flow (arch detect -> resolve nxvim -> build the swap spec), driven
-- against a **fake** `docker` — a real /bin/sh script that answers `uname` with a chosen
-- platform and exits 0 for everything else. Hermetic: no Docker, no network, no host. The
-- daemon is never actually spawned; the argv the connector *builds* is what's asserted. Run
-- with `nxvim --test-plugin .`.

local backends = require("nxvim-remote-containers.backends")
local provision = require("nxvim-remote-containers.provision")

-- Write a fake `docker` into a fresh temp dir and return its path. `uname` is the platform
-- string `docker exec <c> uname -sm` prints; `reachable = false` makes that call exit 1.
-- `installed` controls whether `docker exec <c> test -x <path>` succeeds (binary = "install"
-- reuse path) or fails (would trigger a download — not exercised here).
local function make_fake_docker(uname, reachable, installed)
  return nx.async(function()
    local dir = vim.fn.stdpath("cache") .. "/nxvim-remote-containers-test/" .. nx.uuid()
    nx.await(nx.fs_local.mkdir(dir, { recursive = true }))
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
    nx.await(nx.fs_local.write(path, body))
    nx.await(nx.run_local({ cmd = { "chmod", "+x", path } }))
    return path
  end)()
end

nx.test.describe("resolve (docker, binary = path)", function()
  nx.test.it("detects the platform and builds the daemon spawn spec", function()
    local docker = nx.await(make_fake_docker("Linux x86_64", true, false))
    local opts =
      { docker = docker, remote_nxvim = "nxvim", binary = "path", config_source = "remote" }
    local spec = nx.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    nx.test.expect(spec.transport.kind).to_be("spawn")
    nx.test.expect(spec.transport.argv).to_equal({
      docker,
      "exec",
      "-i",
      "devbox",
      "nxvim",
      "--daemon",
    })
    nx.test.expect(spec.config_source).to_be("remote")
  end)

  nx.test.it("honors config_source = local (the dev-container shape)", function()
    local docker = nx.await(make_fake_docker("Linux x86_64", true, false))
    local opts =
      { docker = docker, remote_nxvim = "nxvim", binary = "path", config_source = "local" }
    local spec = nx.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    nx.test.expect(spec.config_source).to_be("local")
  end)

  nx.test.it("fails loud when the container is unreachable", function()
    local docker = nx.await(make_fake_docker("Linux x86_64", false, false))
    local opts = { docker = docker, remote_nxvim = "nxvim", binary = "path" }
    local ok, err = pcall(function()
      nx.await(provision.resolve(backends.docker(opts), "container://ghost", opts))
    end)
    nx.test.expect(ok).to_be(false)
    nx.test.expect(tostring(err)).to_contain("could not reach")
  end)
end)

nx.test.describe("resolve (docker, binary = install)", function()
  nx.test.it("reuses an already-installed binary at install_dir/nxvim-<platform>", function()
    -- `test -x` succeeds -> no download/copy; the spawn uses the staged path.
    local docker = nx.await(make_fake_docker("Linux x86_64", true, true))
    local opts = {
      docker = docker,
      binary = "install",
      install_dir = "/opt/nxvim",
      config_source = "remote",
    }
    local spec = nx.await(provision.resolve(backends.docker(opts), "container://devbox", opts))
    nx.test.expect(spec.transport.argv).to_equal({
      docker,
      "exec",
      "-i",
      "devbox",
      "/opt/nxvim/nxvim-linux-x86_64",
      "--daemon",
    })
  end)
end)
