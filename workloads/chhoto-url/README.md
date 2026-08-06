<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# chhoto-url

[Chhoto URL](https://github.com/SinTan1729/chhoto-url) — a small self-hosted URL
shortener with a web interface and an HTTP API. A plain composable `kurly.http`
workload keeping its SQLite database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local chhoto = import 'github.com/metio/kurly/workloads/chhoto-url/server.libsonnet';

kurly.list(chhoto())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `chhoto-url` | |
| `image` | `ghcr.io/sintan1729/chhoto-url:7.5.0` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | `/data` |
| `secretName` | `chhoto-url` | supplies `CHHOTO_PASSWORD`, optionally `CHHOTO_API_KEY` |
| `siteUrl` | none | `CHHOTO_SITE_URL`, the public URL links are built from |
| `env` / `resources` / `labels` / `annotations` | | merged over the defaults below |

Serves the web app, the API and the redirects on `:4567`. Compose an exposure
onto it.

## The Secret is not optional

`CHHOTO_PASSWORD` is the only thing guarding the admin interface, and an unset
one leaves it open to anyone who can reach the Service. `CHHOTO_API_KEY` is what
the CLI authenticates with and can be left out if nothing uses it:

```shell
kubectl create secret generic chhoto-url \
  --from-literal=CHHOTO_PASSWORD="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=CHHOTO_API_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Configuration

The stage sets `CHHOTO_DB_URL=/data/urls.sqlite`, `CHHOTO_LISTEN_PORT=4567` and
`CHHOTO_SQLITE_USE_WAL_MODE=True`; `env` merges over those, so a key you set
wins. Everything else Chhoto URL reads — slug style and length, redirect method,
public mode, extra protocols — is an env var and goes through `env` too.

Moving the database off `/data` means the volume no longer holds it, so change
`CHHOTO_DB_URL` and the `store` path together or not at all.

## Probes

The admin interface answers a browser and the API answers a key, so an HTTP probe
would be reporting on the authentication rather than on the server. Readiness and
liveness are connection probes on the port.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). WAL mode writes its journal and shared-memory files
beside the database, on the same volume.

## Posture

The image is `FROM scratch` around one static musl binary: no shell, no
entrypoint dropping privileges, nothing written outside the volume. It keeps the
fully restricted default — non-root, read-only root filesystem, all capabilities
dropped, its own user namespace.

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
metadata: { name: kurly, namespace: chhoto-url }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-chhoto-url, namespace: chhoto-url }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/chhoto-url, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: chhoto-url }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-chhoto-url, namespace: chhoto-url }
spec: { sourceRef: { kind: OCIRepository, name: kurly-chhoto-url } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chhoto-url, namespace: chhoto-url }
spec:
  serviceAccountName: chhoto-url-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/chhoto-url/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chhoto-url, importPath: github.com/metio/kurly/workloads/chhoto-url }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: chhoto-url, namespace: chhoto-url }
spec:
  serviceAccountName: chhoto-url-deployer
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
        name: chhoto-url
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chhoto-url }
```

<!-- END generated: jaas-deploy -->
