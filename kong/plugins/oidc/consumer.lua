-- Association d'un utilisateur OIDC à un consumer Kong réel.
--
-- nokia/kong-oidc ne crée aucun consumer : il pose seulement un « credential »
-- dans le contexte de la requête. Les plugins posés sur un consumer (blocage,
-- limitation de débit décidés par l'exécuteur) ne s'appliquent donc pas.
-- Avec `consumer_mapping = true`, on cherche le consumer dont le custom_id vaut
-- « <tenant>:<sub> ». Le tenant fait partie de la clé : deux realms peuvent en
-- théorie émettre le même `sub`.
local M = {}

local POSITIVE_TTL = 60 -- secondes
local NEGATIVE_TTL = 10 -- un consumer créé par l'exécuteur est pris en compte en 10 s au plus

function M.custom_id(tenant_name, sub)
  return tenant_name .. ":" .. sub
end

local function load_consumer(custom_id)
  local consumer, err = kong.db.consumers:select_by_custom_id(custom_id)
  if err then
    return nil, err
  end
  return consumer
end

function M.find(tenant_name, sub)
  if sub == nil then
    return nil
  end
  local custom_id = M.custom_id(tenant_name, sub)
  local consumer, err = kong.cache:get("oidc:consumer:" .. custom_id,
    { ttl = POSITIVE_TTL, neg_ttl = NEGATIVE_TTL }, load_consumer, custom_id)
  if err then
    kong.log.err("consumer lookup failed for '", custom_id, "': ", err)
    return nil
  end
  return consumer
end

return M
