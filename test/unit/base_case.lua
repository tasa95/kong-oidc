-- Classe de base minimale (remplace kong.vendor.classic, absent hors de Kong).
local BaseCase = {}
BaseCase.__index = BaseCase

function BaseCase:extend()
  local cls = {}
  for k, v in pairs(self) do
    if k:find("^__") then cls[k] = v end
  end
  cls.__index = cls
  cls.super = self
  return setmetatable(cls, self)
end

function BaseCase:setUp()
end

function BaseCase:tearDown()
end

return BaseCase
