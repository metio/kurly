<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ente

[Ente](https://ente.io) — a self-hosted, end-to-end-encrypted photo and video backup, a private
alternative to Google Photos. It runs as **two stages**: the **museum** server (a stateless
`kurly.http` API on `:8080` keeping metadata in PostgreSQL and the encrypted blobs in S3-compatible
object storage, so it needs **no PersistentVolume**) and the **web** front end (the browser UI,
Photos on `:3000` plus the sibling album/cast/share apps). The mobile and desktop apps also point at
the museum API directly.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local museum = import 'github.com/metio/kurly/workloads/ente/server.libsonnet';
local web = import 'github.com/metio/kurly/workloads/ente/web.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local seaweedfs = import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet';

kurly.list([
  cnpg(name='ente-db', database='ente'),
  seaweedfs(name='ente-objects'),
  museum(),
  // The web UI reaches the museum from the BROWSER, so apiOrigin is the museum's
  // public URL, not the in-cluster Service.
  web(apiOrigin='https://ente-api.example.com'),
  // The credentials file museum reads (DB DSN + S3 endpoint/bucket/keys + app
  // secrets), assembled by the operator from the database and object-store
  // above — kurly authors no Secret. Fill it from your secret store:
  kurly.externalSecret('ente', { name: 'vault', kind: 'ClusterSecretStore' }, [
    { secretKey: 'credentials.yaml', remoteRef: { key: 'ente/credentials' } },
  ]),
])
```

## Storage and dependencies

Museum needs two things it does not provision itself:

- **PostgreSQL** — a plain PostgreSQL (no extension), so a stock `cnpg-cluster` works directly.
- **S3-compatible object storage** — where the encrypted blobs live. Any S3 endpoint works; the
  example runs [seaweedfs](../seaweedfs/) in-cluster, but a managed bucket (Backblaze B2, Wasabi,
  MinIO, Garage) is equally fine.

Museum reads its base config from `configurations/local.yaml` baked into the image and merges the
operator's **credentials file** — a `credentials.yaml` carrying the DB DSN, the S3
endpoint/bucket/keys, and the app secrets (`key.encryption`, `key.hash`, `jwt.secret`). Supply it as
a Secret named by `credentialsSecret` (default `ente-credentials`), mounted at `/credentials`, with
`ENTE_CREDENTIALS_FILE` pointing at it — kurly authors **no Secret**. Any single value can instead be
set through an `ENTE_`-prefixed environment variable (`db.host` → `ENTE_DB_HOST`).

Stateless — no PVC — so scale it by replicas. Compose an exposure onto `:8080` for the clients to
reach.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: ente }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ente, namespace: ente }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ente, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ente }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ente, namespace: ente }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ente } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ente-server, namespace: ente }
spec:
  serviceAccountName: ente-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ente/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ente, importPath: github.com/metio/kurly/workloads/ente }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ente-web, namespace: ente }
spec:
  serviceAccountName: ente-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local web = import 'github.com/metio/kurly/workloads/ente/web.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(web())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ente, importPath: github.com/metio/kurly/workloads/ente }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ente, namespace: ente }
spec:
  serviceAccountName: ente-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ente-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ente-server }
    - name: web
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ente-web
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ente-web }
```

<!-- END generated: jaas-deploy -->
