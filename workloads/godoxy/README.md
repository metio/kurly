<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# godoxy

[GoDoxy](https://github.com/yusing/godoxy) — a reverse proxy that routes to backends and issues certificates for them, driven from a web interface. A composable `kurly.http` workload keeping its route configuration on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local godoxy = import 'github.com/metio/kurly/workloads/godoxy/server.libsonnet';
kurly.list(godoxy())
```

Upstream's own deployment reads a Docker socket and discovers its routes from container labels. A pod has no such socket, so nothing is discovered here and the routes are the files under `/app/config` on the volume — written through the WebUI, or placed there beforehand. Neither `DOCKER_HOST` nor a socket-proxy sidecar is rendered: a route naming a Docker container is not reachable from a Kubernetes Service anyway.

TLS belongs to the exposure. `GODOXY_HTTPS_ADDR` is empty and HTTP/3 is off, so GoDoxy opens no TLS listener — the cluster terminates TLS in the Ingress or HTTPRoute composed onto this workload, and GoDoxy's own autocert wants a DNS-01 provider token and a wildcard record, which is a second certificate authority in a cluster that already has one. Set `GODOXY_HTTPS_ADDR` through `env` and add a matching `kurly.extraPort` to get it back.

The API port (`:8888`) is published rather than left on the loopback address the image defaults to: the WebUI's browser and any probe reach it from outside the pod's network namespace.

kurly authors no Secret. `GODOXY_API_USER` and `GODOXY_API_PASSWORD` are **required** unless OIDC is configured — without them the process exits before it serves anything — and `GODOXY_API_JWT_SECRET` signs the session tokens, so an unset one logs everybody out on every restart.

Both probes ask the port rather than a path: the proxy entrypoint answers with whatever a configured route names, or a 404 for a host it does not know, and the API answers 401 until a session exists.

Single writer — one route configuration on a ReadWriteOnce volume, so one replica, recreated rather than rolled.

Serves the proxy entrypoint, which is also where the WebUI is answered by hostname, on `:8080`.

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
metadata: { name: kurly, namespace: godoxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-godoxy, namespace: godoxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/godoxy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: godoxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-godoxy, namespace: godoxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-godoxy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: godoxy, namespace: godoxy }
spec:
  serviceAccountName: godoxy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/godoxy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-godoxy, importPath: github.com/metio/kurly/workloads/godoxy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: godoxy, namespace: godoxy }
spec:
  serviceAccountName: godoxy-deployer
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
        name: godoxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: godoxy }
```

<!-- END generated: jaas-deploy -->
