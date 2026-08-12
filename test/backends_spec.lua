-- The backend descriptors (docker / ssh): URL parsing + the argv they build. Pure — no
-- external tools — so these run anywhere. Run with `bemtvi --test-plugin .`.

local backends = require("bemtvi-remotes.backends")

local OPTS = {
  docker = "docker",
  ssh = "ssh",
  scp = "scp",
  control_persist = "60",
  control_dir = "/tmp/cm",
}

btv.test.describe("docker backend (container://)", function()
  local d = backends.docker(OPTS)

  btv.test.it("parses container://<name> into the container ref", function()
    local t = d.parse("container://devbox")
    btv.test.expect(t.ref).to_be("devbox")
    btv.test.expect(t.display).to_be("devbox")
  end)

  btv.test.it("builds the `docker exec` daemon spawn argv (stdin open)", function()
    local t = d.parse("container://devbox")
    btv.test.expect(d.spawn_argv(t, "bemtvi")).to_equal({
      "docker",
      "exec",
      "-i",
      "devbox",
      "bemtvi",
      "--daemon",
    })
  end)

  btv.test.it("builds an exec argv for a remote command", function()
    local t = d.parse("container://devbox")
    btv.test.expect(d.exec_argv(t, { "uname", "-sm" })).to_equal({
      "docker",
      "exec",
      "devbox",
      "uname",
      "-sm",
    })
  end)

  btv.test.it("builds a `docker cp` argv to stage a binary", function()
    local t = d.parse("container://devbox")
    btv.test.expect(d.copy_argv(t, "/local/bemtvi", "/remote/bemtvi")).to_equal({
      "docker",
      "cp",
      "/local/bemtvi",
      "devbox:/remote/bemtvi",
    })
  end)

  btv.test.it("rejects a malformed / option-injecting container URL", function()
    btv.test.expect(pcall(d.parse, "container://")).to_be(false)
    btv.test.expect(pcall(d.parse, "container://-rm")).to_be(false)
  end)
end)

btv.test.describe("ssh backend (ssh://)", function()
  local s = backends.ssh(OPTS)

  btv.test.it("parses ssh://user@host:port", function()
    local t = s.parse("ssh://me@box.example:2222")
    btv.test.expect(t.dest).to_be("me@box.example")
    btv.test.expect(t.port).to_be("2222")
  end)

  btv.test.it("parses a bare ssh://host (no user, no port)", function()
    local t = s.parse("ssh://box")
    btv.test.expect(t.dest).to_be("box")
    btv.test.expect(t.port).to_be(nil)
  end)

  btv.test.it("builds the daemon spawn argv with control-master multiplexing", function()
    local t = s.parse("ssh://box")
    local argv = s.spawn_argv(t, "bemtvi")
    -- program, the mux options, `--`, dest, then `bemtvi --daemon`
    btv.test.expect(argv[1]).to_be("ssh")
    btv.test.expect(argv).to_contain("ControlMaster=auto")
    btv.test.expect(argv).to_contain("--")
    btv.test.expect(argv).to_contain("box")
    btv.test.expect(argv[#argv - 1]).to_be("bemtvi")
    btv.test.expect(argv[#argv]).to_be("--daemon")
  end)

  btv.test.it("passes the ssh port with -p and threads the control path", function()
    local t = s.parse("ssh://box:2222")
    local argv = s.exec_argv(t, { "uname", "-sm" })
    btv.test.expect(argv).to_contain("-p")
    btv.test.expect(argv).to_contain("2222")
    -- a ControlPath=<socket> option is present
    local has_cp = false
    for _, a in ipairs(argv) do
      if a:match("^ControlPath=") then
        has_cp = true
      end
    end
    btv.test.expect(has_cp).to_be(true)
  end)

  btv.test.it("builds a teardown argv (`ssh -O exit`)", function()
    local t = s.parse("ssh://box")
    local argv = s.teardown_argv(t)
    btv.test.expect(argv).to_contain("-O")
    btv.test.expect(argv).to_contain("exit")
    btv.test.expect(argv[#argv]).to_be("box")
  end)

  btv.test.it("rejects an option-injecting host or user", function()
    btv.test.expect(pcall(s.parse, "ssh://-oProxyCommand=evil")).to_be(false)
    btv.test.expect(pcall(s.parse, "ssh://")).to_be(false)
  end)
end)
