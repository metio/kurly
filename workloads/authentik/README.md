<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# authentik

[authentik](https://goauthentik.io) — a self-hosted identity provider and SSO: OAuth2, SAML,
LDAP, forward-auth and more. It runs as **two workloads** on the same image — a web/API `server`
and a background `worker` — backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/authentik/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/authentik/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='authentik-db', database='authentik')).items,
  kurly.list(server()).items,
  kurly.list(worker()).items,
]))
```

Both stages read the PostgreSQL/Redis connection (`AUTHENTIK_POSTGRESQL__*`,
`AUTHENTIK_REDIS__*`) and `AUTHENTIK_SECRET_KEY` from a shared Secret (`authentik-secrets`) via
`envFrom` — kurly authors **no Secret**. The server serves on `:9000`; the worker has no Service.
Stateless (state lives in PostgreSQL/Redis).
