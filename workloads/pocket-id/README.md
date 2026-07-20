<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pocket-id

[Pocket ID](https://pocket-id.org) — a simple, self-hosted OIDC provider that lets people log in to your apps with passkeys, no passwords. A `kurly.http` workload on the official image; with the default SQLite backend its database and keys on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pocketId = import 'github.com/metio/kurly/workloads/pocket-id/server.libsonnet';
kurly.list(pocketId(appUrl='https://id.example.com'))
```

Set `appUrl` to the public HTTPS URL — passkeys are bound to that origin. Data at `/app/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:1411`.
