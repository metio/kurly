<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# caddy

[Caddy](https://github.com/caddyserver/caddy) — a web server, static file server and reverse proxy with a config API. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local caddy = import 'github.com/metio/kurly/workloads/caddy/server.libsonnet';
kurly.list(caddy(caddyfile=|||
  :8080 {
    reverse_proxy backend:3000
  }
|||))
```

`caddyfile` is Caddy's own configuration language, mounted verbatim at `/etc/caddy/Caddyfile` — kurly does not model it. The default serves the static site the image ships, so the stage boots as it stands.

The site address is a bare port, so Caddy serves plain HTTP and never asks for a certificate: TLS belongs to the exposure composed onto this workload, where the cluster already terminates it. That is what keeps `/data` and `/config` scratch volumes and lets the Deployment scale horizontally. A Caddyfile that names a public hostname instead wants a `kurly.store` at `/data`, so issued certificates survive a restart.

Serves on `:8080`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: caddy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-caddy, namespace: caddy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/caddy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: caddy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-caddy, namespace: caddy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-caddy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: caddy, namespace: caddy }
spec:
  serviceAccountName: caddy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/caddy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-caddy, importPath: github.com/metio/kurly/workloads/caddy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: caddy, namespace: caddy }
spec:
  serviceAccountName: caddy-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: caddy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: caddy }
```

<!-- END generated: jaas-deploy -->
