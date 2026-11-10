local M = {}

local function shouldIgnoreRequest(patterns, path)
  if patterns then
    for _, pattern in ipairs(patterns) do
      if string.find(path, pattern) ~= nil then
        return true
      end
    end
  end
  return false
end

-- `path` : chemin de la requête ; à défaut, ngx.var.uri (compatibilité).
function M.shouldProcessRequest(config, path)
  return not shouldIgnoreRequest(config.filters, path or ngx.var.uri)
end

return M
