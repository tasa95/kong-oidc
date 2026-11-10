local lu = require("luaunit")

TestToken = require("test.unit.mockable_case"):extend()

function TestToken:setUp()
  TestToken.super.setUp(self)
  self.utils = require("kong.plugins.oidc.utils")
end

function TestToken:tearDown()
  TestToken.super.tearDown(self)
end

function TestToken:test_access_token_authorization_missing()
  lu.assertFalse(self.utils.has_bearer_access_token())
end

function TestToken:test_access_token_bearer_missing()
  self.request.headers.Authorization = "Basic xxx"
  lu.assertFalse(self.utils.has_bearer_access_token())
end

function TestToken:test_access_token_bearer_exists()
  self.request.headers.Authorization = "Bearer xxx"
  lu.assertTrue(self.utils.has_bearer_access_token())
end

lu.run()
