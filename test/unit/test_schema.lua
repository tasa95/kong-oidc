local lu = require("luaunit")

TestSchema = require("test.unit.base_case"):extend()

-- typedefs n'existe que dans Kong : substitut qui accepte les surcharges.
package.preload["kong.db.schema.typedefs"] = function()
  local function typedef(base)
    return setmetatable(base, { __call = function(self, overrides)
      local copy = {}
      for k, v in pairs(self) do copy[k] = v end
      for k, v in pairs(overrides or {}) do copy[k] = v end
      return copy
    end })
  end
  return setmetatable({}, { __index = function(_, name) return typedef({ type = "string", typedef = name }) end })
end

local schema = require("kong.plugins.oidc.schema")

function TestSchema:test_name()
  lu.assertEquals(schema.name, "oidc")
  lu.assertNil(schema.no_consumer) -- ancien format supprimé
end

function TestSchema:test_legacy_config_valid()
  lu.assertTrue(schema.check_tenants({ tenants = {}, client_id = "a", client_secret = "b", discovery = "c" }))
end

function TestSchema:test_empty_config_invalid()
  local ok, err = schema.check_tenants({ tenants = {} })
  lu.assertNil(ok)
  lu.assertStrContains(err, "tenants")
end

function TestSchema:test_duplicate_tenant_names()
  local ok, err = schema.check_tenants({ tenants = {
    { name = "a", hosts = { "a" } }, { name = "a", hosts = { "b" } } } })
  lu.assertNil(ok)
  lu.assertStrContains(err, "duplicate")
end

function TestSchema:test_tenant_needs_criterion_unless_default()
  local ok = schema.check_tenants({ tenants = { { name = "a" } } })
  lu.assertNil(ok)
  lu.assertTrue(schema.check_tenants({ tenants = { { name = "a" } }, default_tenant = "a" }))
end

function TestSchema:test_unknown_default_tenant()
  local ok, err = schema.check_tenants({ tenants = { { name = "a", hosts = { "a" } } }, default_tenant = "b" })
  lu.assertNil(ok)
  lu.assertStrContains(err, "default_tenant")
end

function TestSchema:test_redis_storage_requires_host()
  local ok = schema.check_tenants({ tenants = { { name = "a", hosts = { "a" } } }, session_storage = "redis" })
  lu.assertNil(ok)
end

lu.run()
