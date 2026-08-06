<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ergo

[Ergo](https://ergo.chat/) — a modern IRCv3 daemon written in Go, with the account
services, the bouncer and the message history that other networks bolt on as
separate programs built into the server itself. A plain composable `kurly.http`
workload on the official image; its configuration, its database and its TLS
material all live in `/ircd` on a PersistentVolume, so it needs nothing else.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ergo = import 'github.com/metio/kurly/workloads/ergo/server.libsonnet';

kurly.list(ergo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ergo` | |
| `image` | `ghcr.io/ergochat/ergo:v2.19.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the whole state (`/ircd`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves plaintext IRC on `:6667` and IRC-over-TLS on `:6697` — route both as TCP
through a LoadBalancer or a Gateway `TCPRoute`. An HTTP exposure fits neither.

## First boot writes the configuration, and keeps it

The entrypoint copies the image's default configuration to `/ircd/ircd.yaml` **only
when that file is absent**, prints a freshly generated `admin` oper password to the
log as it does so, and then never touches it again. Two consequences:

- read that password out of the first pod's log if you want it — it is not stored
  anywhere else and it is not printed again
- change anything by editing the file on the volume; a newer image will not update
  it for you

The certificate pair the server makes for `:6697` is **self-signed** and regenerated
only when missing. Put a real one in place of `/ircd/fullchain.pem` and
`/ircd/privkey.pem` for anything a client outside the cluster connects to.

## Persistence

One embedded database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). Two servers opening the same database is not something
either of them will sort out afterwards.

The volume is also the working directory, which is what makes the relative paths in
the shipped configuration (`ircd.db`, `fullchain.pem`) resolve there. `/tmp` is a
scratch because the entrypoint builds the first configuration there before moving it
onto the volume — without it nothing is ever generated.

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
metadata: { name: kurly, namespace: ergo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ergo, namespace: ergo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ergo, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ergo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ergo, namespace: ergo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ergo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ergo, namespace: ergo }
spec:
  serviceAccountName: ergo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ergo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ergo, importPath: github.com/metio/kurly/workloads/ergo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ergo, namespace: ergo }
spec:
  serviceAccountName: ergo-deployer
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
        name: ergo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ergo }
```

<!-- END generated: jaas-deploy -->
