-- Options de session (lua-resty-session 4.x) propres à chaque tenant.
--
-- Isolation entre tenants, à trois niveaux :
--   * cookie distinct (`oidc_<tenant>`) : le navigateur garde une session par tenant ;
--   * `audience` = nom du tenant : lua-resty-session refuse une session émise
--     pour une autre audience, même si le cookie est renommé par l'attaquant ;
--   * secret distinct : sans `session_secret` propre au tenant, il est dérivé
--     du secret maître par HMAC(secret maître, « kong-oidc:session:<tenant> »).
--     Un cookie d'un tenant ne se déchiffre donc pas avec la clé d'un autre.
-- En stockage Redis, chaque tenant a en plus son propre préfixe de clés.
local M = {}

local function derive_secret(master, tenant_name)
  return ngx.hmac_sha1(master, "kong-oidc:session:" .. tenant_name)
end

function M.secret(config, t)
  if t.session_secret then
    return t.session_secret
  end
  if config.session_secret then
    return derive_secret(config.session_secret, t.name)
  end
  return nil
end

function M.options(config, t)
  local opts = {
    audience = t.name,
    cookie_name = "oidc_" .. t.name,
    cookie_same_site = "Lax",
    cookie_http_only = true,
    cookie_secure = config.session_cookie_secure == true,
  }

  local secret = M.secret(config, t)
  if secret then
    opts.secret = secret
  else
    -- Sans secret, lua-resty-session tire une clé aléatoire par worker nginx :
    -- les sessions cassent d'un worker à l'autre et à chaque redémarrage.
    kong.log.warn("no session_secret configured for tenant '", t.name, "'")
  end

  if config.session_storage == "redis" then
    opts.storage = "redis"
    opts.redis = {
      host = config.session_redis_host,
      port = config.session_redis_port or 6379,
      username = config.session_redis_username,
      password = config.session_redis_password,
      database = config.session_redis_database,
      prefix = "oidc:" .. t.name,
    }
  end

  return opts
end

return M
