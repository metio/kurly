<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# authelia

[Authelia](https://www.authelia.com) — a self-hosted authentication and authorization gateway that adds single sign-on and 2FA in front of your other apps, via a reverse proxy's forward-auth. A `kurly.http` workload on the official image; its `configuration.yml` mounted as a ConfigMap, with the default SQLite storage on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local authelia = import 'github.com/metio/kurly/workloads/authelia/server.libsonnet';
kurly.list(authelia(config={ /* your Authelia configuration.yml */ }))
```

`config` is Authelia's own `configuration.yml`, mounted verbatim — kurly does not model it. The default is a **minimal skeleton that must be completed** for your domain, identity backend and access rules. The session/storage/JWT secrets come from a Secret via `envFrom` (as `AUTHELIA_*` env) — kurly authors **no Secret**. Data at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:9091`.
