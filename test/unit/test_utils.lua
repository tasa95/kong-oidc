local lu = require("luaunit")

TestUtils = require("test.unit.mockable_case"):extend()

function TestUtils:setUp()
  TestUtils.super.setUp(self)
  self.utils = require("kong.plugins.oidc.utils")
end

function TestUtils:tearDown()
  TestUtils.super.tearDown(self)
end

function TestUtils:testRedirectUriPath()
  local ngx = {
    var = { scheme = "http", host = "1.2.3.4", request_uri = "" },
    req = { get_uri_args = function() return nil end },
  }
  ngx.var.request_uri = "/path?some=stuff"
  lu.assertEquals(self.utils.get_redirect_uri_path(ngx), "/path/")

  ngx.var.request_uri = "/long/path/"
  lu.assertEquals(self.utils.get_redirect_uri_path(ngx), "/long/path")

  ngx.req.get_uri_args = function() return { code = 1 } end
  lu.assertEquals(self.utils.get_redirect_uri_path(ngx), "/long/path/")
end

-- Signature historique get_options(config, ngx) : mode mono-tenant.
function TestUtils:testOptions()
  local opts = self.utils.get_options({
    client_id = 1,
    client_secret = 2,
    discovery = "d",
    scope = "openid",
    response_type = "code",
    ssl_verify = "no",
    token_endpoint_auth_method = "client_secret_post",
    introspection_endpoint_auth_method = "client_secret_basic",
    filters = "pattern1,pattern2,pattern3",
    logout_path = "/logout",
    redirect_after_logout_uri = "/login",
  }, { var = { request_uri = "/path" },
    req = { get_uri_args = function() return nil end } })

  lu.assertEquals(opts.tenant, "default")
  lu.assertEquals(opts.client_id, 1)
  lu.assertEquals(opts.client_secret, 2)
  lu.assertEquals(opts.discovery, "d")
  lu.assertEquals(opts.scope, "openid")
  lu.assertEquals(opts.response_type, "code")
  lu.assertEquals(opts.ssl_verify, "no")
  lu.assertEquals(opts.token_endpoint_auth_method, "client_secret_post")
  lu.assertEquals(opts.introspection_endpoint_auth_method, "client_secret_basic")
  lu.assertEquals(opts.redirect_uri, "/path/")
  lu.assertEquals(opts.logout_path, "/logout")
  lu.assertEquals(opts.redirect_after_logout_uri, "/login")
  lu.assertItemsEquals(opts.filters, { "pattern1", "pattern2", "pattern3" })
end

function TestUtils:testOptionsForPrefixedTenant()
  local t = { name = "acme", path_prefix = "/t/acme/", client_id = "c", discovery = "d" }
  local opts = self.utils.get_options({ timeout = 5 }, t, ngx)
  lu.assertEquals(opts.tenant, "acme")
  lu.assertEquals(opts.redirect_uri, "/t/acme/oidc/callback")
  lu.assertEquals(opts.logout_path, "/t/acme/logout")
  lu.assertEquals(opts.timeout, 5)
end

function TestUtils:testRequiredRoles()
  lu.assertTrue(self.utils.has_required_role({}, nil))
  lu.assertTrue(self.utils.has_required_role({ roles = { "a", "validator" } }, { "validator" }))
  lu.assertFalse(self.utils.has_required_role({ roles = { "user" } }, { "validator" }))
  lu.assertFalse(self.utils.has_required_role({}, { "validator" }))
  lu.assertFalse(self.utils.has_required_role({ roles = "validator" }, { "validator" }))
end

function TestUtils:testSanitizeHeaderValue()
  lu.assertEquals(self.utils.sanitize_header_value('bad"\r\nX-Evil: 1'), "badX-Evil: 1")
end

lu.run()
