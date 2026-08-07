<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gitproxy

[FINOS Git Proxy](https://github.com/finos/git-proxy) — it sits between a
developer and an upstream git host, holds every outgoing push, applies rules to it
and releases it only once somebody has approved. A plain composable `kurly.http`
workload; the approval records and the held pushes live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gitproxy = import 'github.com/metio/kurly/workloads/gitproxy/server.libsonnet';

kurly.list(gitproxy())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gitproxy` | |
| `image` | `finos/git-proxy:v2.0.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/app/.data` |
| `env` / `resources` / `labels` / `annotations` | | |

## Two ports, two audiences

`:8080` is the web UI and the API — compose the exposure onto that one. `:8000` is
the git endpoint a developer sets as their push remote, published on the Service
beside it as the `git` port; route it to wherever the developers are, with a
LoadBalancer, a NodePort or a TCP route.

## Change the secret and the password first

The configuration baked into the image is the project's own example: the cookie
that authenticates a session is signed with a **published secret**, and the local
authentication backend creates the well-known `admin` account on first start.
Supply your own configuration and change that password before anything can reach
the instance.

The `authorisedList` in that same example configuration names one repository —
the project's own. Until it is replaced, that is the only push the proxy will
consider.

## Less hardened, deliberately

The image runs as an unprivileged account, so the hardened defaults stand, with
one exception: **the root filesystem is writable**. The entrypoint writes the UI's
runtime configuration into the built asset directory it also serves from, and the
proxy clones each held push into its own tree beside it — neither path can be an
emptyDir without hiding the files that ship there.

## Persistence

The file-backed database and the held pushes sit on a ReadWriteOnce volume, so
this is **one replica, recreated** (never rolled): two servers deciding
independently which pushes have been approved is not a state you want to
reconcile afterwards.

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
metadata: { name: kurly, namespace: gitproxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gitproxy, namespace: gitproxy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gitproxy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gitproxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gitproxy, namespace: gitproxy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gitproxy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gitproxy, namespace: gitproxy }
spec:
  serviceAccountName: gitproxy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gitproxy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gitproxy, importPath: github.com/metio/kurly/workloads/gitproxy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gitproxy, namespace: gitproxy }
spec:
  serviceAccountName: gitproxy-deployer
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
        name: gitproxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gitproxy }
```

<!-- END generated: jaas-deploy -->
