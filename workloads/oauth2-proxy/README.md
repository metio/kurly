<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# oauth2-proxy

[OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) — a reverse proxy and forward-auth service that puts an OAuth2/OIDC login in front of your other apps (delegating to Keycloak, authentik, Pocket ID, Google, GitHub…). A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local oauth2proxy = import 'github.com/metio/kurly/workloads/oauth2-proxy/server.libsonnet';
kurly.list(oauth2proxy())
```

Provider settings, client id/secret and the cookie secret come from a Secret via `envFrom` (`OAUTH2_PROXY_*`) — kurly authors **no Secret**. Front an app (`OAUTH2_PROXY_UPSTREAMS`) or wire it as a reverse proxy's forward-auth at `/oauth2/auth`. Serves on `:4180`.
