<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# flaresolverr

[FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) — a proxy that solves
Cloudflare and DDoS-GUARD browser challenges by driving a headless browser, so scrapers
and the *arr indexers can reach protected sites. A plain composable `kurly.http` workload
on the official image; it holds no persistent state, so it is a plain **stateless**
Deployment.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local flaresolverr = import 'github.com/metio/kurly/workloads/flaresolverr/server.libsonnet';
kurly.list(flaresolverr())
```

Other workloads (e.g. [Jackett](../jackett/), [Prowlarr](../prowlarr/)) point their
FlareSolverr URL at `http://flaresolverr:8191`. It is an internal helper, so it usually
needs no exposure. Serves on `:8191`.
