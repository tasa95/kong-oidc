-- Plugin oidc pour Kong 3.x, multi-tenant.
-- Kong 3 n'a plus `kong.plugins.base_plugin` : un plugin est une table simple
-- portant PRIORITY et VERSION.
local utils = require("kong.plugins.oidc.utils")
local filter = require("kong.plugins.oidc.filter")
local session = require("kong.plugins.oidc.session")
local tenant = require("kong.plugins.oidc.tenant")
local consumer = require("kong.plugins.oidc.consumer")

local OidcHandler = {
  PRIORITY = 1000,
  VERSION = "2.0.0",
}

local function openidc()
  return require("resty.openidc")
end

local function introspect(oidcConfig)
  if utils.has_bearer_access_token() or oidcConfig.bearer_only == "yes" then
    local res, err = openidc().introspect(oidcConfig)
    if err then
      if oidcConfig.bearer_only == "yes" then
        kong.log.debug("introspection failed for tenant '", oidcConfig.tenant, "': ", err)
        local challenge = 'Bearer realm="' .. utils.sanitize_header_value(oidcConfig.realm)
          .. '",error="' .. utils.sanitize_header_value(err) .. '"'
        return nil, utils.exit(401, "Unauthorized", { ["WWW-Authenticate"] = challenge })
      end
      return nil
    end
    kong.log.debug("OidcHandler introspect succeeded, requested path: ", kong.request.get_path())
    return res
  end
  return nil
end

local function make_oidc(oidcConfig, session_opts)
  kong.log.debug("OidcHandler calling authenticate, requested path: ", kong.request.get_path())
  local res, err = openidc().authenticate(oidcConfig, nil, nil, session_opts)
  if err then
    kong.log.err("authentication failed for tenant '", oidcConfig.tenant, "': ", err)
    if oidcConfig.recovery_page_path then
      kong.log.debug("Entering recovery page: ", oidcConfig.recovery_page_path)
      return nil, kong.response.exit(302, nil, { Location = oidcConfig.recovery_page_path })
    end
    return nil, utils.exit(500, "Authentication error")
  end
  return res
end

local function authenticated(config, oidcConfig, user)
  if not utils.has_required_role(user, oidcConfig.required_roles) then
    kong.log.notice("user lacks required role for tenant '", oidcConfig.tenant, "'")
    return utils.exit(403, "Forbidden")
  end
  local c
  if config.consumer_mapping then
    c = consumer.find(oidcConfig.tenant, user.sub)
  end
  utils.injectUser(user, c)
end

local function handle(config, oidcConfig, t)
  local response
  if oidcConfig.introspection_endpoint then
    local exited
    response, exited = introspect(oidcConfig)
    if exited then
      return exited
    end
    if response then
      return authenticated(config, oidcConfig, response)
    end
  end

  local exited
  response, exited = make_oidc(oidcConfig, session.options(config, t))
  if exited then
    return exited
  end
  if response then
    if response.user then
      local stop = authenticated(config, oidcConfig, response.user)
      if stop then
        return stop
      end
    elseif oidcConfig.required_roles and #oidcConfig.required_roles > 0 then
      -- Rôle exigé mais aucune information utilisateur : on refuse.
      return utils.exit(403, "Forbidden")
    end
    if response.access_token then
      utils.injectAccessToken(response.access_token)
    end
    if response.id_token then
      utils.injectIDToken(response.id_token)
    end
  end
end

function OidcHandler:access(config)
  utils.clear_identity_headers()

  local path = kong.request.get_path()
  local t, err = tenant.resolve(config, kong.request.get_host(), path)
  if not t then
    kong.log.info(err)
    return utils.exit(404, "Unknown tenant")
  end
  utils.injectTenant(t.name)

  local oidcConfig = utils.get_options(config, t, ngx)

  if filter.shouldProcessRequest(oidcConfig, path) then
    handle(config, oidcConfig, t)
  else
    kong.log.debug("OidcHandler ignoring request, path: ", path)
  end

  kong.log.debug("OidcHandler done")
end

return OidcHandler
