local lu = require("luaunit")

TestSession = require("test.unit.mockable_case"):extend()

function TestSession:setUp()
  TestSession.super.setUp(self)
  self.session = require("kong.plugins.oidc.session")
end

function TestSession:tearDown()
  TestSession.super.tearDown(self)
end

function TestSession:test_secret_derived_per_tenant()
  local config = { session_secret = "master" }
  lu.assertEquals(self.session.secret(config, { name = "a" }), "hmac(master,kong-oidc:session:a)")
  lu.assertNotEquals(self.session.secret(config, { name = "a" }), self.session.secret(config, { name = "b" }))
end

function TestSession:test_tenant_secret_overrides_master()
  lu.assertEquals(self.session.secret({ session_secret = "m" }, { name = "a", session_secret = "own" }), "own")
end

function TestSession:test_missing_secret_warns()
  local opts = self.session.options({}, { name = "a" })
  lu.assertNil(opts.secret)
  lu.assertTrue(self:log_contains("no session_secret"))
end

function TestSession:test_redis_storage_prefixed_by_tenant()
  local opts = self.session.options({
    session_secret = "m", session_storage = "redis", session_redis_host = "redis-sessions",
    session_redis_username = "kong", session_redis_password = "pw",
  }, { name = "acme" })
  lu.assertEquals(opts.storage, "redis")
  lu.assertEquals(opts.redis.host, "redis-sessions")
  lu.assertEquals(opts.redis.port, 6379)
  lu.assertEquals(opts.redis.prefix, "oidc:acme")
  lu.assertEquals(opts.audience, "acme")
  lu.assertFalse(opts.cookie_secure)
end

lu.run()
