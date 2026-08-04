<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# opengist

[Opengist](https://github.com/thomiceli/opengist) — a self-hosted pastebin where
every snippet is a real Git repository, so a gist keeps its full revision history
and can be cloned, pushed to and forked. A plain composable `kurly.http` workload
that keeps the repositories, its SQLite database and the Bleve search index on a
PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local opengist = import 'github.com/metio/kurly/workloads/opengist/server.libsonnet';

kurly.list(opengist())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `opengist` | |
| `image` | `ghcr.io/thomiceli/opengist:1.15.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the data volume (`/opengist`) |
| `externalUrl` | unset | the server's own public URL |
| `secretName` | `opengist` | supplies `OG_SECRET_KEY` |
| `env` | `{}` | extra `OG_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:6157` — compose an exposure onto it:

```jsonnet
kurly.list([
  opengist(externalUrl='https://gist.example.com')
  + kurly.expose.ownGateway('gist.example.com', 'istio', tls='opengist-tls'),
  kurly.certificate('opengist-tls', ['gist.example.com'], 'letsencrypt-prod'),
])
```

## The Secret

`OG_SECRET_KEY` signs session cookies. Left unset, Opengist generates 32 random
bytes **at startup**, so every restart logs everyone out — which is why this
workload takes it from a Secret rather than leaving it to the app. kurly mints no
Secret; create one holding that key, or fill it from a secret store with
`kurly.externalSecret`.

```shell
kubectl create secret generic opengist \
  --from-literal=OG_SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Git over SSH

The built-in SSH server is enabled by default and listens on `:2222`, carried on
the Service as a second port. HTTP exposure does not route it: give it a
`TCPRoute`, a `LoadBalancer` Service or a NodePort if clones over SSH should work
from outside the cluster, and set `externalUrl` so the clone commands the UI shows
name the right host. Set `OG_SSH_GIT_ENABLED=disabled` through `env` to turn it off
entirely; the port stays declared but nothing answers on it.

## Persistence

The repositories, the SQLite database and the search index share one ReadWriteOnce
volume, so this is **one replica, recreated** (never rolled) to keep two pods off
the files — the same single-writer discipline as [gogs](../gogs/). Pointing
`OG_DB_URI` at external PostgreSQL or MySQL moves the database off the volume, but
the gist repositories stay on it, so the single writer stands either way.

## Running unprivileged

The image's entrypoint chowns the data directory and drops privileges with `su`
when it is started as root — the pattern that normally forces a workload to relax
kurly's hardened defaults. Opengist's entrypoint takes a different path when it is
already non-root and execs the server directly, so pinning a uid keeps the
**restricted** posture intact: no root, no privilege escalation, no capabilities.
`fsGroup` is what makes the volume writable instead.

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
metadata: { name: kurly, namespace: opengist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-opengist, namespace: opengist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/opengist, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: opengist }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-opengist, namespace: opengist }
spec: { sourceRef: { kind: OCIRepository, name: kurly-opengist } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: opengist, namespace: opengist }
spec:
  serviceAccountName: opengist-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/opengist/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-opengist, importPath: github.com/metio/kurly/workloads/opengist }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: opengist, namespace: opengist }
spec:
  serviceAccountName: opengist-deployer
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
        name: opengist
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: opengist }
```

<!-- END generated: jaas-deploy -->
