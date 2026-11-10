local lu = require("luaunit")

TestTenant = require("test.unit.mockable_case"):extend()

function TestTenant:setUp()
  TestTenant.super.setUp(self)
  self.tenant = require("kong.plugins.oidc.tenant")
  self.config = { tenants = {
    { name = "exact", hosts = { "app.example.com" } },
    { name = "wild", hosts = { "*.example.com" } },
    { name = "prefix", path_prefix = "/t/acme" },
    { name = "longer", path_prefix = "/t/acme/admin" },
    { name = "both", hosts = { "app.example.com" }, path_prefix = "/api" },
    { name = "noop" },
  } }
end

function TestTenant:tearDown()
  TestTenant.super.tearDown(self)
end

function TestTenant:resolve(host, path)
  local t, err = self.tenant.resolve(self.config, host, path)
  return t and t.name, err
end

function TestTenant:test_legacy_config_gives_default_tenant()
  local t = self.tenant.resolve({ client_id = "c" }, "x", "/")
  lu.assertEquals(t.name, "default")
  lu.assertEquals(t.client_id, "c")
  lu.assertTrue(t.legacy)
end

function TestTenant:test_exact_host_beats_wildcard()
  lu.assertEquals(self:resolve("app.example.com", "/"), "exact")
  lu.assertEquals(self:resolve("APP.Example.com", "/"), "exact")
  lu.assertEquals(self:resolve("other.example.com", "/"), "wild")
end

function TestTenant:test_wildcard_does_not_match_apex_or_lookalike()
  lu.assertNil(self:resolve("example.com", "/"))
  lu.assertNil(self:resolve("evilexample.com", "/"))
end

function TestTenant:test_host_and_prefix_combined()
  lu.assertEquals(self:resolve("app.example.com", "/api/x"), "both")
  lu.assertEquals(self:resolve("app.example.com", "/other"), "exact")
end

function TestTenant:test_longest_prefix_wins()
  lu.assertEquals(self:resolve("x", "/t/acme"), "prefix")
  lu.assertEquals(self:resolve("x", "/t/acme/page"), "prefix")
  lu.assertEquals(self:resolve("x", "/t/acme/admin/users"), "longer")
end

function TestTenant:test_prefix_boundary()
  lu.assertNil(self:resolve("x", "/t/acmebad"))
end

function TestTenant:test_tenant_without_criteria_only_as_default()
  lu.assertNil(self:resolve("nowhere", "/"))
  self.config.default_tenant = "noop"
  lu.assertEquals(self:resolve("nowhere", "/"), "noop")
end

function TestTenant:test_default_path()
  lu.assertEquals(self.tenant.default_path({ path_prefix = "/t/a/" }, "/logout"), "/t/a/logout")
  lu.assertEquals(self.tenant.default_path({}, "/logout"), "/logout")
end

lu.run()
