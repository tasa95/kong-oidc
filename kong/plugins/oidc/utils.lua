local cjson = require("cjson")
local tenant = require("kong.plugins.oidc.tenant")

local M = {}

-- En-têtes d'identité transmis à l'amont. Ils sont toujours effacés à
-- l'entrée : un client ne doit pas pouvoir les fournir lui-même (sur un
-- chemin filtré, par exemple) pour usurper une identité.
M.IDENTITY_HEADERS = { "X-Userinfo", "X-Access-Token", "X-ID-Token", "X-Tenant" }

local function parseFilters(csvFilters)
  local filters = {}
  if csvFilters ~= nil then
    for pattern in string.gmatch(csvFilters, "[^,]+") do
      table.insert(filters, pattern)
    end
  end
  return filters
end

-- Comportement historique de nokia/kong-oidc, conservé pour le mode mono-tenant
-- quand aucune URI de retour n'est configurée.
function M.get_redirect_uri_path(ngx)
  local function drop_query()
    local uri = ngx.var.request_uri
    local x = uri:find("?")
    if x then
      return uri:sub(1, x - 1)
    else
      return uri
    end
  end

  local function tackle_slash(path)
    local args = ngx.req.get_uri_args()
    if args and args.code then
      return path
    elseif path == "/" then
      return "/cb"
    elseif path:sub(-1) == "/" then
      return path:sub(1, -2)
    else
      return path .. "/"
    end
  end

  return tackle_slash(drop_query())
end

local function redirect_uri(t, ngx)
  if t.redirect_uri then
    return t.redirect_uri
  end
  if t.redirect_uri_path then
    return t.redirect_uri_path
  end
  if t.legacy then
    return M.get_redirect_uri_path(ngx)
  end
  return tenant.default_path(t, "/oidc/callback")
end

-- Options passées à lua-resty-openidc pour le tenant `t`.
-- `t` vaut `config` lui-même en mode mono-tenant (appel historique à 2 arguments).
function M.get_options(config, t, ngx_)
  if ngx_ == nil then
    -- Signature historique : get_options(config, ngx)
    ngx_ = t
    t = tenant.resolve(config, nil, nil)
  end

  local logout_path = t.logout_path
  if logout_path == nil then
    logout_path = t.legacy and "/logout" or tenant.default_path(t, "/logout")
  end

  return {
    tenant = t.name,
    client_id = t.client_id,
    client_secret = t.client_secret,
    discovery = t.discovery,
    introspection_endpoint = t.introspection_endpoint,
    timeout = config.timeout,
    introspection_endpoint_auth_method = t.introspection_endpoint_auth_method,
    bearer_only = t.bearer_only,
    realm = t.realm,
    redirect_uri = redirect_uri(t, ngx_),
    scope = t.scope,
    response_type = t.response_type,
    ssl_verify = t.ssl_verify,
    token_endpoint_auth_method = t.token_endpoint_auth_method,
    recovery_page_path = t.recovery_page_path,
    filters = parseFilters(t.filters),
    logout_path = logout_path,
    redirect_after_logout_uri = t.redirect_after_logout_uri or "/",
    required_roles = t.required_roles,
  }
end

-- Réponse d'erreur. Le détail technique est journalisé, pas renvoyé au client.
function M.exit(httpStatusCode, message, headers)
  return kong.response.exit(httpStatusCode, { message = message }, headers)
end

function M.clear_identity_headers()
  for _, h in ipairs(M.IDENTITY_HEADERS) do
    kong.service.request.clear_header(h)
  end
end

function M.injectAccessToken(accessToken)
  kong.service.request.set_header("X-Access-Token", accessToken)
end

function M.injectIDToken(idToken)
  local tokenStr = cjson.encode(idToken)
  kong.service.request.set_header("X-ID-Token", ngx.encode_base64(tokenStr))
end

function M.injectTenant(tenantName)
  kong.service.request.set_header("X-Tenant", tenantName)
  -- Partagé avec les autres plugins (redis-log, deny-list).
  kong.ctx.shared.oidc_tenant = tenantName
end

-- `consumer` : consumer Kong réel associé à l'utilisateur, ou nil.
function M.injectUser(user, consumer)
  local credential = {
    id = user.sub,
    username = user.preferred_username,
  }
  kong.client.authenticate(consumer, credential)
  kong.ctx.shared.oidc_sub = user.sub
  kong.ctx.shared.oidc_username = user.preferred_username

  -- Format historique de X-Userinfo conservé (l'analyseur en dépend).
  local tmp_user = user
  tmp_user.id = user.sub
  tmp_user.username = user.preferred_username
  local userinfo = cjson.encode(tmp_user)
  kong.service.request.set_header("X-Userinfo", ngx.encode_base64(userinfo))
end

-- Vrai si aucun rôle n'est exigé, ou si l'utilisateur porte au moins l'un d'eux
-- dans la revendication `roles` (mapper Keycloak « realm roles » vers `roles`).
function M.has_required_role(user, required_roles)
  if required_roles == nil or #required_roles == 0 then
    return true
  end
  local roles = type(user) == "table" and user.roles
  if type(roles) ~= "table" then
    return false
  end
  for _, wanted in ipairs(required_roles) do
    for _, role in ipairs(roles) do
      if role == wanted then
        return true
      end
    end
  end
  return false
end

function M.has_bearer_access_token()
  local header = kong.request.get_header("Authorization")
  if header and header:find(" ") then
    local divider = header:find(' ')
    if string.lower(header:sub(0, divider - 1)) == string.lower("Bearer") then
      return true
    end
  end
  return false
end

-- Neutralise ce qui pourrait casser un en-tête WWW-Authenticate.
function M.sanitize_header_value(value)
  return (tostring(value):gsub('[%c"\\]', ""))
end

return M
