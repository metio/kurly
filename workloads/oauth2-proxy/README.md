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

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: oauth2-proxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-oauth2-proxy, namespace: oauth2-proxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/oauth2-proxy, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: oauth2-proxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-oauth2-proxy, namespace: oauth2-proxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-oauth2-proxy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: oauth2-proxy, namespace: oauth2-proxy }
spec:
  serviceAccountName: oauth2-proxy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/oauth2-proxy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-oauth2-proxy, importPath: github.com/metio/kurly/workloads/oauth2-proxy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: oauth2-proxy, namespace: oauth2-proxy }
spec:
  serviceAccountName: oauth2-proxy-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: oauth2-proxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: oauth2-proxy }
```

<!-- END generated: jaas-deploy -->
