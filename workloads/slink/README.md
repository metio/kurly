<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# slink

[Slink](https://github.com/andrii-kryvoviaz/slink) — an image sharing platform:
upload a picture, get a link, and decide who may follow it, with albums, expiring
shares and password-protected shares. A plain composable `kurly.http` workload on
the official image; it stores everything in SQLite, so it needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local slink = import 'github.com/metio/kurly/workloads/slink/server.libsonnet';

kurly.list(slink(origin='https://images.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `slink` | |
| `image` | `anirdev/slink:v1.9.6` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | `/app/slink/images` |
| `dataSize` / `dataStorageClass` | `5Gi` / cluster default | `/app/var/data` |
| `origin` | unset | the URL people visit — see below |
| `env` / `resources` / `labels` / `annotations` | | |

## Set `origin`, or nothing can be uploaded

The SvelteKit client checks the `Origin` header of every state-changing request
against `ORIGIN`, which the image defaults to `http://localhost:3000`. Exposed
under any other name, the site loads, browses and then rejects every upload and
every login with a CSRF error — which reads as a broken application rather than a
misconfigured one. Set `origin` to the URL the browser will use.

## Ports

The client listens on `:3000` and proxies `/api` and `/image` to the PHP API on
`:8080` inside the pod. `:3000` is the front door and the only port this workload
publishes; compose an exposure onto it.

## Less hardened, deliberately

The entrypoint generates a JWT keypair, hands the storage tree to the `slink`
account and drops privileges to it through s6 — all of which it can only do
starting from root. The root filesystem is writable because supervisord, Caddy and
the Symfony cache write inside the image's own tree, and the generated keypair is
installed into `/services/api/config/jwt`.

## Persistence

Two volumes, because the halves grow at completely different rates: the uploaded
images at `/app/slink/images` and the SQLite databases at `/app/var/data`. The
second one also holds the keypair generated on first start, which signs every
session — restoring the images without it signs everyone out permanently.

Single writer on SQLite, so **one replica, recreated** (never rolled) to keep two
pods off the files.

## First start takes a while

Generating a 4096-bit RSA key and migrating two databases happens before anything
listens, so the workload carries a startup probe with a generous budget rather
than a slack liveness delay. A `StageSet` deploying it needs a `timeout` past that
budget as well.

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
metadata: { name: kurly, namespace: slink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-slink, namespace: slink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/slink, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: slink }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-slink, namespace: slink }
spec: { sourceRef: { kind: OCIRepository, name: kurly-slink } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: slink, namespace: slink }
spec:
  serviceAccountName: slink-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/slink/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-slink, importPath: github.com/metio/kurly/workloads/slink }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: slink, namespace: slink }
spec:
  serviceAccountName: slink-deployer
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
        name: slink
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: slink }
```

<!-- END generated: jaas-deploy -->
