-- Sélection du tenant d'une requête.
--
-- Un tenant correspond à un fournisseur OIDC (un realm Keycloak) et à un
-- client. Il est choisi à partir de l'hôte et du chemin de la requête :
--   1. on retient les tenants dont TOUS les critères déclarés correspondent
--      (hôtes et préfixe de chemin) ;
--   2. parmi eux, le plus spécifique gagne : hôte exact > hôte générique
--      (« *.exemple.fr ») > pas d'hôte, puis préfixe de chemin le plus long ;
--   3. à égalité, l'ordre de déclaration tranche ;
--   4. sinon `default_tenant`, sinon aucun tenant (la requête est refusée).
--
-- La sélection ne repose jamais sur un en-tête choisi par le client (type
-- « X-Tenant ») : l'hôte et le chemin sont déjà ceux qui routent la requête
-- dans Kong.
local M = {}

M.DEFAULT_NAME = "default"

local PROVIDER_KEYS = {
  "client_id", "client_secret", "discovery", "introspection_endpoint",
  "introspection_endpoint_auth_method", "bearer_only", "realm", "redirect_uri",
  "redirect_uri_path", "scope", "response_type", "ssl_verify",
  "token_endpoint_auth_method", "recovery_page_path", "logout_path",
  "redirect_after_logout_uri", "filters", "required_roles", "session_secret",
}

-- Tenant implicite construit à partir des champs historiques (mono-tenant).
local function legacy_tenant(config)
  local t = { name = M.DEFAULT_NAME, legacy = true }
  for _, key in ipairs(PROVIDER_KEYS) do
    t[key] = config[key]
  end
  return t
end

local function normalize_prefix(prefix)
  if prefix == nil or prefix == "" or prefix == "/" then
    return nil
  end
  if prefix:sub(-1) == "/" then
    prefix = prefix:sub(1, -2)
  end
  return prefix
end

-- Retourne 2 (hôte exact), 1 (hôte générique) ou nil (pas de correspondance).
local function match_host(patterns, host)
  local best
  for _, pattern in ipairs(patterns) do
    pattern = pattern:lower()
    if pattern == host then
      return 2
    end
    if pattern:sub(1, 2) == "*." then
      local suffix = pattern:sub(2) -- « .exemple.fr »
      if #host > #suffix and host:sub(-#suffix) == suffix then
        best = 1
      end
    end
  end
  return best
end

-- « /t/acme » correspond à « /t/acme » et « /t/acme/... », pas à « /t/acmeX ».
local function match_prefix(prefix, path)
  if path == prefix then
    return true
  end
  return path:sub(1, #prefix + 1) == prefix .. "/"
end

local function score(t, host, path)
  local host_score = 0
  if t.hosts and #t.hosts > 0 then
    host_score = match_host(t.hosts, host)
    if not host_score then
      return nil
    end
  end

  local prefix = normalize_prefix(t.path_prefix)
  local prefix_len = 0
  if prefix then
    if not match_prefix(prefix, path) then
      return nil
    end
    prefix_len = #prefix
  end

  if host_score == 0 and prefix_len == 0 then
    return nil -- tenant sans critère : uniquement accessible comme tenant par défaut
  end

  -- L'hôte prime toujours sur la longueur du préfixe.
  return host_score * 100000 + prefix_len
end

function M.resolve(config, host, path)
  local tenants = config.tenants
  if tenants == nil or #tenants == 0 then
    return legacy_tenant(config)
  end

  host = (host or ""):lower()
  path = path or "/"

  local best, best_score
  for _, t in ipairs(tenants) do
    local s = score(t, host, path)
    if s and (best_score == nil or s > best_score) then
      best, best_score = t, s
    end
  end
  if best then
    return best
  end

  if config.default_tenant then
    for _, t in ipairs(tenants) do
      if t.name == config.default_tenant then
        return t
      end
    end
  end

  return nil, "no tenant matches host '" .. host .. "' and path '" .. path .. "'"
end

-- Chemin par défaut d'un tenant (callback, déconnexion), placé sous son préfixe
-- pour que deux tenants servis par le même hôte ne partagent pas ces chemins.
function M.default_path(t, suffix)
  return (normalize_prefix(t.path_prefix) or "") .. suffix
end

return M
