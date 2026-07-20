<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lldap

[LLDAP](https://github.com/lldap/lldap) — a light LDAP implementation for authentication:
a simple, opinionated user/group directory with a friendly web UI, a lightweight stand-in
for OpenLDAP that apps authenticate against. A plain composable `kurly.http` workload on
the official image; with the default SQLite backend its directory lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lldap = import 'github.com/metio/kurly/workloads/lldap/server.libsonnet';
kurly.list(lldap())
```

Apps bind over LDAP on `:3890`, a separate port — add a Service for it (a raw `+` patch).
LLDAP needs `LLDAP_JWT_SECRET` and `LLDAP_LDAP_USER_PASS` (the admin password) from a
Secret via `envFrom` — kurly authors **no Secret**. Point it at an external
PostgreSQL/MySQL (`LLDAP_DATABASE_URL`) to scale past the single SQLite writer. Directory
at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on
`:17170`.
