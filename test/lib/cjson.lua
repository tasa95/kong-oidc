-- Substitut minimal de lua-cjson pour les tests hors OpenResty.
return {
  encode = function() return "encoded" end,
  decode = function() return {} end,
}
