local lu = require("luaunit")

TestIntrospect = require("test.unit.mockable_case"):extend()

function TestIntrospect:setUp()
  TestIntrospect.super.setUp(self)
  package.loaded["resty.openidc"] = nil
  self.openidc = {
    introspect = function() return { sub = "sub" }, nil end,
    authenticate = function() return {}, nil end,
  }
  package.preload["resty.openidc"] = function() return self.openidc end
  self.handler = require("kong.plugins.oidc.handler")
end

function TestIntrospect:tearDown()
  TestIntrospect.super.tearDown(self)
end

function TestIntrospect:test_access_token_exists()
  self.request.headers.Authorization = "Bearer xxx"
  self.handler:access({ introspection_endpoint = "x" })
  lu.assertTrue(self:log_contains("introspect succeeded"))
  lu.assertEquals(self.headers["X-Userinfo"], "b64(encoded)")
end

function TestIntrospect:test_no_authorization_header()
  local authenticated = false
  self.openidc.authenticate = function() authenticated = true; return {}, nil end
  self.handler:access({ introspection_endpoint = "x" })
  lu.assertTrue(authenticated)
  lu.assertFalse(self:log_contains("err"))
  lu.assertNil(self.headers["X-Userinfo"])
end

lu.run()
