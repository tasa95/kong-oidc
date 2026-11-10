-- Simule ngx et le PDK Kong (kong.request, kong.service.request, kong.response...).
local BaseCase = require("test.unit.base_case")
local MockableCase = BaseCase:extend()

-- Modules du plugin à recharger à chaque test (ils capturent leurs dépendances).
local PLUGIN_MODULES = {
  "kong.plugins.oidc.handler", "kong.plugins.oidc.utils", "kong.plugins.oidc.filter",
  "kong.plugins.oidc.session", "kong.plugins.oidc.tenant", "kong.plugins.oidc.consumer",
}

function MockableCase:setUp()
  MockableCase.super:setUp()
  local this = self
  self.logs = {}
  self.headers = {}        -- en-têtes envoyés à l'amont
  self.cleared = {}        -- en-têtes effacés
  self.exit_status = nil
  self.exit_body = nil
  self.exit_headers = nil
  self.credential = nil
  self.consumer = nil
  self.request = { host = "localhost", path = "/", headers = {} }

  local function log(level)
    return function(...)
      local parts = { level }
      for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
      this.logs[#this.logs + 1] = table.concat(parts, " ")
    end
  end

  self.mocked_ngx = {
    DEBUG = "debug",
    ERR = "error",
    HTTP_UNAUTHORIZED = 401,
    ctx = {},
    header = {},
    var = { request_uri = "/", uri = "/" },
    req = {
      get_uri_args = function() end,
    },
    log = function(...) end,
    encode_base64 = function(x) return "b64(" .. x .. ")" end,
    hmac_sha1 = function(key, data) return "hmac(" .. key .. "," .. data .. ")" end,
  }
  self.ngx = _G.ngx
  _G.ngx = self.mocked_ngx

  self.kong = _G.kong
  _G.kong = {
    log = {
      debug = log("debug"), info = log("info"), notice = log("notice"),
      warn = log("warn"), err = log("err"),
    },
    request = {
      get_path = function() return this.request.path end,
      get_host = function() return this.request.host end,
      get_header = function(name) return this.request.headers[name] end,
    },
    service = { request = {
      set_header = function(h, v) this.headers[h] = v end,
      clear_header = function(h) this.cleared[h] = true end,
    } },
    response = {
      exit = function(status, body, headers)
        this.exit_status, this.exit_body, this.exit_headers = status, body, headers
        return status
      end,
    },
    client = {
      authenticate = function(consumer, credential)
        this.consumer, this.credential = consumer, credential
      end,
    },
    ctx = { shared = {} },
    cache = {
      get = function(_, key, opts, cb, ...) return cb(...) end,
    },
    db = { consumers = {
      select_by_custom_id = function(_, custom_id)
        return this.consumers_by_custom_id and this.consumers_by_custom_id[custom_id]
      end,
    } },
  }

  self.cjson = package.loaded.cjson
  package.loaded.cjson = nil
  package.preload["cjson"] = function()
    return {
      encode = function() return "encoded" end,
      decode = function() return { sub = "sub" } end,
    }
  end

  for _, m in ipairs(PLUGIN_MODULES) do package.loaded[m] = nil end
end

function MockableCase:tearDown()
  MockableCase.super:tearDown()
  _G.ngx = self.ngx
  _G.kong = self.kong
  package.loaded.cjson = self.cjson
end

function MockableCase:log_contains(str)
  return table.concat(self.logs, "//"):find(str, 1, true) and true or false
end

return MockableCase
