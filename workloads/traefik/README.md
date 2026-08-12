<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# traefik

[Traefik](https://traefik.io) — an edge router that discovers its own
configuration from the cluster: it watches Ingress, IngressRoute and Gateway API
objects and routes traffic to the Services behind them, obtaining certificates as
it goes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local traefik = import 'github.com/metio/kurly/workloads/traefik/ingress.libsonnet';

kurly.list(traefik(namespace='traefik', acmeEmail='ops@example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `traefik` | |
| `image` | the pinned upstream image | |
| `namespace` | `traefik` | where the ServiceAccount lives — required |
| `replicas` | `2` | forced to 1 when `acmeEmail` is set |
| `acmeEmail` | none | turns on the Let's Encrypt resolver |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the certificate store (`/data`) |
| `extraRules` | `[]` | added to the cluster-wide grant |
| `extraArgs` | `[]` | appended to Traefik's flags |
| `resources` / `env` / `labels` / `annotations` | | |

Serves `:8000` (web) and `:8443` (websecure), with the dashboard and metrics on
`:9000` — compose an exposure onto the entry points, usually a LoadBalancer
Service.

## Unprivileged ports, deliberately

Traefik's own image listens on `:80` and `:443`, which a container without
`NET_BIND_SERVICE` cannot bind. Rather than grant that capability, the entry
points here are 8000 and 8443 and the Service maps 80 and 443 onto them — the
arrangement that keeps the hardened posture, and the one a LoadBalancer in front
makes invisible to clients.

## The grant

Traefik reads Ingress objects across the cluster, which is what an edge router
does and why the grant is cluster-wide. It covers the Kubernetes Ingress provider
and the Gateway API. Traefik's **own** CRDs (IngressRoute, Middleware and the
rest) are not granted, because a cluster that has not installed them would be
given permissions on kinds that do not exist:

```jsonnet
traefik(namespace='traefik', extraRules=[
  { apiGroups: ['traefik.io'], resources: ['ingressroutes', 'middlewares'], verbs: ['get', 'list', 'watch'] },
])
```

The dashboard is not exposed and `api.insecure` is off. Traefik's dashboard has no
authentication of its own, so publishing it publishes the routing table of the
whole cluster.

## Certificates

`acmeEmail` turns on a Let's Encrypt resolver storing its account and certificates
on the volume, and pins the deployment to one replica: the store is a file on a
ReadWriteOnce volume, and two routers racing for the same account produce
rate-limit failures rather than certificates. Without it Traefik serves its own
self-signed certificate, which is fine behind something that already terminates
TLS.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: traefik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-traefik, namespace: traefik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/traefik, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: traefik }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-traefik, namespace: traefik }
spec: { sourceRef: { kind: OCIRepository, name: kurly-traefik } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: traefik, namespace: traefik }
spec:
  serviceAccountName: traefik-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local ingress = import 'github.com/metio/kurly/workloads/traefik/ingress.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(ingress())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-traefik, importPath: github.com/metio/kurly/workloads/traefik }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: traefik, namespace: traefik }
spec:
  serviceAccountName: traefik-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: ingress
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: traefik
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: traefik }
```

<!-- END generated: jaas-deploy -->
