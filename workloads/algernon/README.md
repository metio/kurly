<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# algernon

[Algernon](https://github.com/xyproto/algernon) — a self-contained web server that
serves static files, Markdown and Lua scripts, with templates and a built-in
database. A composable `kurly.http` workload: the served directory and the Bolt
database share one PersistentVolume, so nothing external is needed.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local algernon = import 'github.com/metio/kurly/workloads/algernon/server.libsonnet';

kurly.list(algernon())
```

Serves on `:3000` — compose an exposure onto it.

| Parameter | Default | Notes |
|---|---|---|
| `name` | `algernon` | |
| `image` | `xyproto/algernon:prod` | |
| `port` | `3000` | container and Service port |
| `contentPath` | `/data/www` | the directory served |
| `databaseFile` | `/data/algernon.db` | the Bolt database |
| `extraArgs` | `[]` | flags appended before the positionals (`--theme`, `--nolimit`, …) |
| `storageSize` / `storageClass` | `5Gi` / cluster default | mounted at `/data` |
| `env` / `resources` / `labels` / `annotations` | | |

## The image's entrypoint is replaced

The published `prod` entrypoint serves HTTPS on `:443` from a certificate at
`/etc/algernon/cert.pem` and redirects `:80` — a workload that will not start until
somebody puts a keypair into the image's second volume. In a cluster TLS is
terminated by the exposure, not by the application, so this workload runs the same
server in plain HTTP mode with the port and the database file stated explicitly.

Anything else Algernon takes goes in `extraArgs`, which is spliced in before the
served directory and the address.

## It carries no site

A fresh volume is empty and Algernon answers with a directory listing until you put
something under `www/` on it. Ship your pages by composing a `kurly.config` onto the
workload and pointing `contentPath` at the mount, by pre-populating the volume, or
by pointing `contentPath` at a volume you mount yourself.

The Bolt database sits beside the served directory rather than inside it, so a
directory listing never offers it for download.

## Persistence

One Bolt file (users, permissions, key-value data) on a ReadWriteOnce volume, so
this is **one replica, recreated** (never rolled). Two servers on one Bolt file is
not something Bolt sorts out afterwards.

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
metadata: { name: kurly, namespace: algernon }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-algernon, namespace: algernon }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/algernon, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: algernon }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-algernon, namespace: algernon }
spec: { sourceRef: { kind: OCIRepository, name: kurly-algernon } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: algernon, namespace: algernon }
spec:
  serviceAccountName: algernon-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/algernon/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-algernon, importPath: github.com/metio/kurly/workloads/algernon }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: algernon, namespace: algernon }
spec:
  serviceAccountName: algernon-deployer
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
        name: algernon
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: algernon }
```

<!-- END generated: jaas-deploy -->
