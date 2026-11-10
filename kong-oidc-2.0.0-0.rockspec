package = "kong-oidc"
version = "2.0.0-0"
source = {
    url = "git+https://github.com/tasa95/kong-oidc",
    branch = "kong3-multitenant",
}
description = {
    summary = "OpenID Connect Relying Party plugin for Kong 3.x, multi-tenant",
    detailed = [[
        Fork of nokia/kong-oidc ported to Kong 3.x. One plugin instance can
        serve several tenants (one OpenID Connect provider and client per
        tenant), selected by host and/or path prefix, with isolated sessions.
    ]],
    homepage = "https://github.com/tasa95/kong-oidc",
    license = "Apache 2.0"
}
dependencies = {
    -- 1.8.0 : dernière version compatible avec lua-resty-session 4.0.5 embarqué
    -- par Kong 3.9 (les 1.9.x exigent lua-resty-session == 4.2.0 et
    -- lua-resty-openssl >= 1.8.0).
    "lua-resty-openidc == 1.8.0-1"
}
build = {
    type = "builtin",
    modules = {
    ["kong.plugins.oidc.consumer"] = "kong/plugins/oidc/consumer.lua",
    ["kong.plugins.oidc.filter"] = "kong/plugins/oidc/filter.lua",
    ["kong.plugins.oidc.handler"] = "kong/plugins/oidc/handler.lua",
    ["kong.plugins.oidc.schema"] = "kong/plugins/oidc/schema.lua",
    ["kong.plugins.oidc.session"] = "kong/plugins/oidc/session.lua",
    ["kong.plugins.oidc.tenant"] = "kong/plugins/oidc/tenant.lua",
    ["kong.plugins.oidc.utils"] = "kong/plugins/oidc/utils.lua"
    }
}
