local lu = require("luaunit")

TestHandler = require("test.unit.mockable_case"):extend()

function TestHandler:setUp()
  TestHandler.super.setUp(self)
  package.loaded["resty.openidc"] = nil
  self.openidc = {
    authenticate = function() return {}, nil end,
  }
  package.preload["resty.openidc"] = function() return self.openidc end
  self.handler = require("kong.plugins.oidc.handler")
end

function TestHandler:tearDown()
  TestHandler.super.tearDown(self)
end

function TestHandler:test_kong3_plugin_shape()
  lu.assertEquals(self.handler.PRIORITY, 1000)
  lu.assertIsString(self.handler.VERSION)
  lu.assertNil(self.handler.new) -- plus d'héritage de base_plugin
end

function TestHandler:test_authenticate_ok_no_userinfo()
  self.handler:access({})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertNil(self.headers["X-Userinfo"])
end

function TestHandler:test_authenticate_ok_with_userinfo()
  self.openidc.authenticate = function()
    return { user = { sub = "sub", preferred_username = "alice" } }, nil
  end
  self.handler:access({})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertEquals(self.credential.id, "sub")
  lu.assertEquals(self.credential.username, "alice")
  lu.assertEquals(self.headers["X-Userinfo"], "b64(encoded)")
  lu.assertEquals(kong.ctx.shared.oidc_sub, "sub")
end

function TestHandler:test_authenticate_ok_with_no_accesstoken()
  self.handler:access({})
  lu.assertNil(self.headers["X-Access-Token"])
end

function TestHandler:test_accesstoken_not_forwarded_by_default()
  self.openidc.authenticate = function() return { access_token = "ACCESS_TOKEN" }, nil end
  self.handler:access({})
  lu.assertNil(self.headers["X-Access-Token"])
end

function TestHandler:test_accesstoken_forwarded_when_enabled()
  self.openidc.authenticate = function() return { access_token = "ACCESS_TOKEN" }, nil end
  self.handler:access({ forward_access_token = true })
  lu.assertEquals(self.headers["X-Access-Token"], "ACCESS_TOKEN")
end

function TestHandler:test_authenticate_ok_with_no_idtoken()
  self.handler:access({})
  lu.assertNil(self.headers["X-ID-Token"])
end

function TestHandler:test_authenticate_ok_with_idtoken()
  self.openidc.authenticate = function() return { id_token = { sub = "sub" } }, nil end
  self.handler:access({})
  lu.assertEquals(self.headers["X-ID-Token"], "b64(encoded)")
end

function TestHandler:test_authenticate_nok_no_recovery()
  self.openidc.authenticate = function() return nil, "boom: secret detail" end
  self.handler:access({})
  lu.assertEquals(self.exit_status, 500)
  -- le détail de l'erreur est journalisé mais pas renvoyé au client
  lu.assertEquals(self.exit_body.message, "Authentication error")
  lu.assertTrue(self:log_contains("secret detail"))
end

function TestHandler:test_authenticate_nok_with_recovery()
  self.openidc.authenticate = function() return nil, "boom" end
  self.handler:access({ recovery_page_path = "/x" })
  lu.assertTrue(self:log_contains("recovery page"))
  lu.assertEquals(self.exit_status, 302)
  lu.assertEquals(self.exit_headers.Location, "/x")
end

function TestHandler:test_introspect_ok_no_userinfo()
  self.openidc.introspect = function() return false, nil end
  self.request.headers.Authorization = "Bearer xxx"
  self.handler:access({ introspection_endpoint = "x" })
  lu.assertTrue(self:log_contains("introspect succeeded"))
end

function TestHandler:test_introspect_ok_with_userinfo()
  self.openidc.introspect = function() return {}, nil end
  self.request.headers.Authorization = "Bearer xxx"
  self.handler:access({ introspection_endpoint = "x" })
  lu.assertTrue(self:log_contains("introspect succeeded"))
  lu.assertEquals(self.headers["X-Userinfo"], "b64(encoded)")
end

function TestHandler:test_bearer_only_with_good_token()
  self.openidc.introspect = function() return { sub = "sub" }, nil end
  self.request.headers.Authorization = "Bearer xxx"
  self.handler:access({ introspection_endpoint = "x", bearer_only = "yes", realm = "kong" })
  lu.assertTrue(self:log_contains("introspect succeeded"))
  lu.assertEquals(self.headers["X-Userinfo"], "b64(encoded)")
end

function TestHandler:test_bearer_only_with_bad_token()
  self.openidc.introspect = function() return {}, "validation failed" end
  self.request.headers.Authorization = "Bearer xxx"
  self.handler:access({ introspection_endpoint = "x", bearer_only = "yes", realm = "kong" })
  lu.assertEquals(self.exit_status, 401)
  lu.assertEquals(self.exit_headers["WWW-Authenticate"], 'Bearer realm="kong",error="validation failed"')
  lu.assertFalse(self:log_contains("introspect succeeded"))
end

-- Sécurité : un client ne peut pas injecter lui-même les en-têtes d'identité.
function TestHandler:test_identity_headers_always_cleared()
  self.handler:access({ filters = "^/public" })
  self.request.path = "/public/x"
  self.handler:access({ filters = "^/public" })
  for _, h in ipairs({ "X-Userinfo", "X-Access-Token", "X-ID-Token", "X-Tenant" }) do
    lu.assertTrue(self.cleared[h], h)
  end
end

-- ===== Multi-tenant =====

local function multi_config()
  return {
    session_secret = "0123456789abcdef0123456789abcdef",
    session_storage = "cookie",
    tenants = {
      { name = "poc", hosts = { "crapi.localhost" }, client_id = "kong-poc",
        client_secret = "s1", discovery = "http://kc/realms/poc/.well-known/openid-configuration" },
      { name = "partner", hosts = { "*.partner.localhost" }, client_id = "kong-partner",
        client_secret = "s2", discovery = "http://kc/realms/partner/.well-known/openid-configuration" },
      { name = "soc", hosts = { "console.localhost" }, client_id = "console",
        client_secret = "s3", discovery = "http://kc/realms/soc/.well-known/openid-configuration",
        required_roles = { "validator" } },
    },
  }
end

function TestHandler:test_tenant_selected_by_host()
  local seen_opts, seen_session
  self.openidc.authenticate = function(opts, _, _, session_opts)
    seen_opts, seen_session = opts, session_opts
    return { user = { sub = "u1" } }, nil
  end
  self.request.host = "app.partner.localhost"
  self.handler:access(multi_config())

  lu.assertEquals(seen_opts.client_id, "kong-partner")
  lu.assertEquals(seen_opts.tenant, "partner")
  lu.assertEquals(seen_opts.redirect_uri, "/oidc/callback")
  lu.assertEquals(seen_session.audience, "partner")
  lu.assertEquals(seen_session.cookie_name, "oidc_partner")
  lu.assertEquals(self.headers["X-Tenant"], "partner")
  lu.assertEquals(kong.ctx.shared.oidc_tenant, "partner")
end

function TestHandler:test_unknown_tenant_rejected()
  local called = false
  self.openidc.authenticate = function() called = true; return {}, nil end
  self.request.host = "evil.localhost"
  self.handler:access(multi_config())
  lu.assertEquals(self.exit_status, 404)
  lu.assertFalse(called)
end

function TestHandler:test_default_tenant_fallback()
  local seen
  self.openidc.authenticate = function(opts) seen = opts; return {}, nil end
  local config = multi_config()
  config.default_tenant = "poc"
  self.request.host = "other.localhost"
  self.handler:access(config)
  lu.assertEquals(seen.client_id, "kong-poc")
end

function TestHandler:test_required_role_missing_is_forbidden()
  self.openidc.authenticate = function()
    return { user = { sub = "u1", roles = { "user" } }, access_token = "AT" }, nil
  end
  self.request.host = "console.localhost"
  self.handler:access(multi_config())
  lu.assertEquals(self.exit_status, 403)
  lu.assertNil(self.headers["X-Userinfo"])
  lu.assertNil(self.headers["X-Access-Token"])
end

function TestHandler:test_required_role_present()
  self.openidc.authenticate = function()
    return { user = { sub = "v1", roles = { "validator" } }, access_token = "AT" }, nil
  end
  self.request.host = "console.localhost"
  local config = multi_config()
  config.forward_access_token = true -- console: the token is its proof of decision
  self.handler:access(config)
  lu.assertNil(self.exit_status)
  lu.assertEquals(self.headers["X-Access-Token"], "AT")
end

function TestHandler:test_sessions_isolated_between_tenants()
  local sessions = {}
  self.openidc.authenticate = function(opts, _, _, session_opts)
    sessions[opts.tenant] = session_opts
    return {}, nil
  end
  local config = multi_config()
  self.request.host = "crapi.localhost"
  self.handler:access(config)
  self.request.host = "console.localhost"
  self.handler:access(config)

  lu.assertNotEquals(sessions.poc.secret, sessions.soc.secret)
  lu.assertNotEquals(sessions.poc.cookie_name, sessions.soc.cookie_name)
  lu.assertNotEquals(sessions.poc.audience, sessions.soc.audience)
end

function TestHandler:test_consumer_mapping()
  self.consumers_by_custom_id = { ["poc:u1"] = { id = "consumer-uuid" } }
  self.openidc.authenticate = function() return { user = { sub = "u1" } }, nil end
  local config = multi_config()
  config.consumer_mapping = true
  self.request.host = "crapi.localhost"
  self.handler:access(config)
  lu.assertEquals(self.consumer.id, "consumer-uuid")

  -- même sub dans un autre tenant : pas le même consumer
  self.consumer = nil
  self.request.host = "a.partner.localhost"
  self.handler:access(config)
  lu.assertNil(self.consumer)
end

lu.run()
