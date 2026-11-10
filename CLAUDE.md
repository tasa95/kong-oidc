# kong-oidc (fork tasa95/kong-oidc) — consignes

Plugin OIDC pour Kong 3.x, multi-tenant. Dépôt git **distinct** du POC : remote `origin` = `git@github.com:tasa95/kong-oidc.git`, branche de travail `kong3-multitenant`. Documentation, commentaires et messages de commit en français, identifiants en anglais.

## Règles de travail

- Ne jamais travailler sur `master` : branche `kong3-multitenant` ou une branche dédiée à partir d'elle.
- Ne pas pousser sans demande explicite de l'utilisateur.
- `bin/run-unit-tests.sh` (ou `test/unit/run.sh`) doit rester à **0 échec** avant tout commit.
- `spec/`, `ci/`, `test/docker/`, `.travis.yml` datent de Kong 0.x/1.0 : obsolètes, ne pas s'en servir comme référence.

## Architecture des modules

| Module | Rôle |
|---|---|
| `handler.lua` | phase access : efface les en-têtes d'identité, résout le tenant, filtre, authentifie |
| `tenant.lua` | sélection du tenant (hôte exact > `*.domaine` > préfixe le plus long > `default_tenant` > 404) |
| `session.lua` | options lua-resty-session 4 par tenant (cookie, audience, secret dérivé, préfixe Redis) |
| `utils.lua` | options lua-resty-openidc, injection des en-têtes, rôles |
| `consumer.lua` | association au consumer Kong `custom_id = <tenant>:<sub>` |
| `schema.lua` | schéma Kong 3 + `check_tenants` (exposé pour les tests) |

## Invariants de sécurité (chacun couvert par un test)

1. Le tenant ne se choisit **jamais** d'après un en-tête fourni par le client ; aucune correspondance → 404, jamais un tenant « au hasard ».
2. `X-Userinfo`, `X-Access-Token`, `X-ID-Token`, `X-Tenant` sont **toujours effacés** en entrée, même sur un chemin filtré.
3. Isolation des sessions : cookie `oidc_<tenant>`, `audience` = tenant, secret propre ou `HMAC(secret maître, "kong-oidc:session:" .. tenant)`, préfixe Redis `oidc:<tenant>`. Ne retirer aucune de ces trois couches.
4. Le détail des erreurs d'authentification est journalisé, **jamais renvoyé** au client.
5. Format de `X-Userinfo` inchangé (base64 du JSON userinfo + `id`, `username`) : l'analyseur et la console en dépendent.
6. `kong.ctx.shared.oidc_tenant / oidc_sub / oidc_username` : contrat avec les plugins `redis-log` et `deny-list` du POC. Ne pas renommer sans les modifier.
7. Préfixe de chemin : `/t/acme` correspond à `/t/acme` et `/t/acme/...`, jamais à `/t/acmeX`.

## Compatibilité

- La configuration mono-tenant historique (champs à plat, `tenants` vide) doit continuer de fonctionner : tenant implicite `default`, ancien calcul de `redirect_uri_path`.
- `lua-resty-openidc == 1.8.0-1` (compatible `lua-resty-session` 4.0.5 de Kong 3.9). `authenticate(opts, nil, nil, session_opts)` : le 4e argument porte les options de session par tenant.
- Changement de champ de configuration : mettre à jour `schema.lua`, `tenant.lua` (`PROVIDER_KEYS`), `utils.get_options`, les tests et le README.

## Tests

```sh
./test/unit/run.sh                 # télécharge luaunit au besoin, LuaJIT ou Lua 5.x
LUA_PATH="./?.lua;./test/lib/?.lua;;" luajit test/unit/test_tenant.lua -o text
```

Les tests simulent `ngx` et le PDK (`test/unit/mockable_case.lua`) : `self.headers` (en-têtes envoyés à l'amont), `self.cleared`, `self.exit_status`, `self.credential`, `self.request.host/path/headers`. Appeler les classes parentes avec `X.super.setUp(self)` (pas `X.super:setUp()`).
