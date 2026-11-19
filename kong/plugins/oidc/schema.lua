-- Schéma Kong 3.x du plugin oidc (multi-tenant).
--
-- Deux façons de configurer le plugin :
--   * multi-tenant : `config.tenants` contient un ou plusieurs tenants, chacun
--     avec son fournisseur OIDC (realm Keycloak), son client et ses critères
--     de sélection (hôtes et/ou préfixe de chemin) ;
--   * mono-tenant (compatibilité avec nokia/kong-oidc) : `config.tenants` est
--     vide et les champs historiques (`client_id`, `discovery`, ...) sont
--     renseignés au niveau de `config`. Ils forment alors un tenant implicite
--     nommé « default ».
local typedefs = require "kong.db.schema.typedefs"

local TENANT_NAME_PATTERN = "^[a-z0-9][a-z0-9_-]*$"

-- Champs propres à un fournisseur OIDC. Réutilisés tels quels pour le tenant
-- implicite (niveau `config`) et pour chaque élément de `config.tenants`.
local function provider_fields(required)
  return {
    { client_id = { type = "string", required = required } },
    { client_secret = { type = "string", required = required, referenceable = true } },
    { discovery = typedefs.url { required = required } },
    { introspection_endpoint = typedefs.url { required = false } },
    { introspection_endpoint_auth_method = { type = "string", required = false } },
    { bearer_only = { type = "string", required = true, default = "no", one_of = { "yes", "no" } } },
    { realm = { type = "string", required = true, default = "kong" } },
    -- URI de retour : chemin (« /oidc/callback ») ou URI absolue.
    { redirect_uri = { type = "string", required = false } },
    -- Ancien nom, conservé pour compatibilité.
    { redirect_uri_path = { type = "string", required = false } },
    { scope = { type = "string", required = true, default = "openid" } },
    { response_type = { type = "string", required = true, default = "code" } },
    { ssl_verify = { type = "string", required = true, default = "no", one_of = { "yes", "no" } } },
    { token_endpoint_auth_method = { type = "string", required = true, default = "client_secret_post" } },
    { recovery_page_path = { type = "string", required = false } },
    { logout_path = { type = "string", required = false } },
    { redirect_after_logout_uri = { type = "string", required = false } },
    -- Motifs Lua séparés par des virgules : chemins non soumis à l'authentification.
    { filters = { type = "string", required = false } },
    -- Rôles exigés (au moins un) dans la revendication `roles` de l'utilisateur.
    { required_roles = { type = "array", required = false, elements = { type = "string" } } },
    -- Secret de session propre au tenant. À défaut, il est dérivé du secret
    -- global et du nom du tenant (voir session.lua).
    { session_secret = { type = "string", required = false, referenceable = true } },
  }
end

local tenant_fields = {
  { name = { type = "string", required = true, match = TENANT_NAME_PATTERN } },
  -- Hôtes servis par ce tenant ; « *.exemple.fr » accepte les sous-domaines.
  { hosts = { type = "array", required = false, elements = typedefs.wildcard_host } },
  -- Préfixe de chemin servi par ce tenant (ex. « /t/acme »).
  { path_prefix = typedefs.path { required = false } },
}
for _, field in ipairs(provider_fields(true)) do
  tenant_fields[#tenant_fields + 1] = field
end

local config_fields = {
  { tenants = {
      type = "array",
      required = true,
      default = {},
      elements = { type = "record", fields = tenant_fields },
  } },
  -- Tenant utilisé quand aucun critère ne correspond. Sans lui, la requête
  -- est refusée (404) : on ne choisit jamais un tenant « au hasard ».
  { default_tenant = { type = "string", required = false, match = TENANT_NAME_PATTERN } },
  { timeout = { type = "number", required = false } },
  -- Secret maître des sessions (32 caractères minimum).
  { session_secret = { type = "string", required = false, referenceable = true, len_min = 32 } },
  { session_storage = { type = "string", required = true, default = "cookie", one_of = { "cookie", "redis" } } },
  { session_redis_host = typedefs.host { required = false } },
  { session_redis_port = typedefs.port { required = false, default = 6379 } },
  { session_redis_username = { type = "string", required = false } },
  { session_redis_password = { type = "string", required = false, referenceable = true } },
  { session_redis_database = { type = "integer", required = false, default = 0 } },
  { session_cookie_secure = { type = "boolean", required = true, default = false } },
  -- Associe l'utilisateur à un consumer Kong réel (custom_id = « <tenant>:<sub> »)
  -- quand il existe, pour que les plugins posés sur ce consumer s'appliquent.
  { consumer_mapping = { type = "boolean", required = true, default = false } },
  -- Forward the Keycloak access token upstream in X-Access-Token. Off by
  -- default: the BFF keeps tokens server-side, upstreams only get the
  -- identity (X-Userinfo). Enable only on the one service that needs the
  -- token (the console, which attaches it to each decision as proof).
  { forward_access_token = { type = "boolean", required = true, default = false } },
}
for _, field in ipairs(provider_fields(false)) do
  config_fields[#config_fields + 1] = field
end

-- Kong passes unset optional fields to entity checks as ngx.null (a truthy
-- userdata), not nil: normalise before testing them.
local null = ngx and ngx.null
local function opt(v)
  if v == null then return nil end
  return v
end

local function check_tenants(config)
  local tenants = opt(config.tenants) or {}
  local default_tenant = opt(config.default_tenant)

  if #tenants == 0 then
    if not (opt(config.client_id) and opt(config.client_secret) and opt(config.discovery)) then
      return nil, "either 'tenants' or 'client_id', 'client_secret' and 'discovery' must be set"
    end
    return true
  end

  local seen = {}
  for _, t in ipairs(tenants) do
    if seen[t.name] then
      return nil, "duplicate tenant name '" .. t.name .. "'"
    end
    seen[t.name] = true

    local hosts = opt(t.hosts)
    local has_hosts = hosts and #hosts > 0
    if not has_hosts and not opt(t.path_prefix) and default_tenant ~= t.name then
      return nil, "tenant '" .. t.name .. "' needs 'hosts' or 'path_prefix' (or must be the default tenant)"
    end
  end

  if default_tenant and not seen[default_tenant] then
    return nil, "default_tenant '" .. default_tenant .. "' is not a declared tenant"
  end

  if config.session_storage == "redis" and not opt(config.session_redis_host) then
    return nil, "'session_redis_host' is required when session_storage is 'redis'"
  end

  return true
end

return {
  name = "oidc",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = config_fields,
        entity_checks = {
          { custom_entity_check = {
              field_sources = { "tenants", "default_tenant", "client_id", "client_secret",
                                "discovery", "session_storage", "session_redis_host" },
              fn = check_tenants,
          } },
        },
    } },
  },
  -- No extra field here: Kong rejects unknown fields in a plugin schema
  -- ("unknown field"). Tests read check_tenants from entity_checks.
}
