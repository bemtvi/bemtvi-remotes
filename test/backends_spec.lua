-- The backend descriptors (docker / ssh): URL parsing + the argv they build. Pure — no
-- external tools — so these run anywhere. Run with `nxvim --test-plugin .`.

local backends = require("nxvim-remotes.backends")

local OPTS = {
  docker = "docker",
  ssh = "ssh",
  scp = "scp",
  control_persist = "60",
  control_dir = "/tmp/cm",
}

nx.test.describe("docker backend (container://)", function()
  local d = backends.docker(OPTS)

  nx.test.it("parses container://<name> into the container ref", function()
    local t = d.parse("container://devbox")
    nx.test.expect(t.ref).to_be("devbox")
    nx.test.expect(t.display).to_be("devbox")
  end)

  nx.test.it("builds the `docker exec` daemon spawn argv (stdin open)", function()
    local t = d.parse("container://devbox")
    nx.test.expect(d.spawn_argv(t, "nxvim")).to_equal({
      "docker",
      "exec",
      "-i",
      "devbox",
      "nxvim",
      "--daemon",
    })
  end)

  nx.test.it("builds an exec argv for a remote command", function()
    local t = d.parse("container://devbox")
    nx.test.expect(d.exec_argv(t, { "uname", "-sm" })).to_equal({
      "docker",
      "exec",
      "devbox",
      "uname",
      "-sm",
    })
  end)

  nx.test.it("builds a `docker cp` argv to stage a binary", function()
    local t = d.parse("container://devbox")
    nx.test.expect(d.copy_argv(t, "/local/nxvim", "/remote/nxvim")).to_equal({
      "docker",
      "cp",
      "/local/nxvim",
      "devbox:/remote/nxvim",
    })
  end)

  nx.test.it("rejects a malformed / option-injecting container URL", function()
    nx.test.expect(pcall(d.parse, "container://")).to_be(false)
    nx.test.expect(pcall(d.parse, "container://-rm")).to_be(false)
  end)
end)

nx.test.describe("ssh backend (ssh://)", function()
  local s = backends.ssh(OPTS)

  nx.test.it("parses ssh://user@host:port", function()
    local t = s.parse("ssh://me@box.example:2222")
    nx.test.expect(t.dest).to_be("me@box.example")
    nx.test.expect(t.port).to_be("2222")
  end)

  nx.test.it("parses a bare ssh://host (no user, no port)", function()
    local t = s.parse("ssh://box")
    nx.test.expect(t.dest).to_be("box")
    nx.test.expect(t.port).to_be(nil)
  end)

  nx.test.it("builds the daemon spawn argv with control-master multiplexing", function()
    local t = s.parse("ssh://box")
    local argv = s.spawn_argv(t, "nxvim")
    -- program, the mux options, `--`, dest, then `nxvim --daemon`
    nx.test.expect(argv[1]).to_be("ssh")
    nx.test.expect(argv).to_contain("ControlMaster=auto")
    nx.test.expect(argv).to_contain("--")
    nx.test.expect(argv).to_contain("box")
    nx.test.expect(argv[#argv - 1]).to_be("nxvim")
    nx.test.expect(argv[#argv]).to_be("--daemon")
  end)

  nx.test.it("passes the ssh port with -p and threads the control path", function()
    local t = s.parse("ssh://box:2222")
    local argv = s.exec_argv(t, { "uname", "-sm" })
    nx.test.expect(argv).to_contain("-p")
    nx.test.expect(argv).to_contain("2222")
    -- a ControlPath=<socket> option is present
    local has_cp = false
    for _, a in ipairs(argv) do
      if a:match("^ControlPath=") then
        has_cp = true
      end
    end
    nx.test.expect(has_cp).to_be(true)
  end)

  nx.test.it("builds a teardown argv (`ssh -O exit`)", function()
    local t = s.parse("ssh://box")
    local argv = s.teardown_argv(t)
    nx.test.expect(argv).to_contain("-O")
    nx.test.expect(argv).to_contain("exit")
    nx.test.expect(argv[#argv]).to_be("box")
  end)

  nx.test.it("rejects an option-injecting host or user", function()
    nx.test.expect(pcall(s.parse, "ssh://-oProxyCommand=evil")).to_be(false)
    nx.test.expect(pcall(s.parse, "ssh://")).to_be(false)
  end)
end)
