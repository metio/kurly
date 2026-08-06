<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# opencloud

[OpenCloud](https://github.com/opencloud-eu/opencloud) — file sync and share with a
web interface, WebDAV and desktop/mobile clients. One process hosts every internal
service, so this is a plain composable `kurly.http` workload: the generated
configuration and the stored files live on two PersistentVolumes and nothing
external is required.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local opencloud = import 'github.com/metio/kurly/workloads/opencloud/server.libsonnet';

kurly.list(opencloud(url='https://cloud.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `opencloud` | |
| `image` | `opencloudeu/opencloud:7.2.2` | |
| `url` | `https://opencloud.example.com` | the address users reach it at — set it |
| `storageSize` / `configSize` / `storageClass` | `50Gi` / `1Gi` / cluster default | `/var/lib/opencloud`, `/etc/opencloud` |
| `port` | `9200` | |
| `secretName` | `opencloud` | holds `IDM_ADMIN_PASSWORD` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI, WebDAV and the APIs on `:9200`:

```jsonnet
kurly.list([
  opencloud(url='https://cloud.example.com')
  + kurly.expose.ownGateway('cloud.example.com', 'istio', tls='opencloud-tls'),
  kurly.certificate('opencloud-tls', ['cloud.example.com'], 'letsencrypt-prod'),
])
```

## The URL is not decoration

`url` has no sane default. OpenCloud hands it to its own web client and to every
OIDC redirect, so an instance reached at a different address serves a UI that
cannot talk to its own backend. Set it to the host the exposure publishes.

TLS is terminated **in front of** the pod (`PROXY_TLS=false`), which is what lets
an ordinary HTTP exposure route to it. Left at its default the proxy answers HTTPS
with a certificate it generated for itself, and every exposure would have to be
told to trust it.

## The first administrator

`opencloud init` runs once, before the server, and writes the configuration the
server refuses to start without. It **mints** the service secrets and signing keys
every internal service authenticates with, so it is guarded by the presence of
`/etc/opencloud/opencloud.yaml`: a second run would issue new ones and orphan
everything the old ones signed.

The Secret named by `secretName` supplies `IDM_ADMIN_PASSWORD` for the first
administrator. It is read **once** — changing it later does not change the
password, because by then it lives hashed in OpenCloud's own identity store. Leave
the key out and init generates a password and prints it to the init container's
log.

## Persistence

Two volumes, deliberately separate: the file blobs and the users database at
`/var/lib/opencloud`, and the generated configuration at `/etc/opencloud`. Losing
the configuration while keeping the blobs leaves an instance that cannot read its
own files, so back both up or neither.

Both are ReadWriteOnce and there is a single writer, so this is **one replica,
recreated** (never rolled) to keep two pods off them.

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
metadata: { name: kurly, namespace: opencloud }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-opencloud, namespace: opencloud }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/opencloud, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: opencloud }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-opencloud, namespace: opencloud }
spec: { sourceRef: { kind: OCIRepository, name: kurly-opencloud } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: opencloud, namespace: opencloud }
spec:
  serviceAccountName: opencloud-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/opencloud/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-opencloud, importPath: github.com/metio/kurly/workloads/opencloud }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: opencloud, namespace: opencloud }
spec:
  serviceAccountName: opencloud-deployer
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
        name: opencloud
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: opencloud }
```

<!-- END generated: jaas-deploy -->
