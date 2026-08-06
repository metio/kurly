<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# zot-oci-registry

[zot](https://github.com/project-zot/zot) — a vendor-neutral container image
registry that stores images in the OCI image layout on disk, rather than in a
layout only it can read. A plain composable `kurly.http` workload on the official
image; the image store lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local zot = import 'github.com/metio/kurly/workloads/zot-oci-registry/server.libsonnet';

kurly.list(zot())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `zot-oci-registry` | |
| `image` | the pinned zot image | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | `/var/lib/registry` |
| `logLevel` | `info` | the image's own config ships `debug` |
| `ui` | `true` | the web UI, and the search and mgmt extensions it reads |
| `cve` | `false` | the vulnerability scanner — see below |
| `config` | `{}` | merged verbatim over the rendered zot config |
| `env` / `resources` / `labels` / `annotations` | | |

## Configuration is a file, not environment

zot reads one JSON document, so the whole configuration is rendered into a
ConfigMap mounted at `/etc/zot` and `config` merges into it **verbatim**. That is
the escape hatch for authentication, access control, sync from an upstream
registry and the S3 storage driver — none of which this workload models, because
zot's schema is large and moves.

```jsonnet
zot(config={
  http: {
    auth: { htpasswd: { path: '/secrets/htpasswd' } },
    accessControl: { repositories: { '**': { anonymousPolicy: ['read'] } } },
  },
})
+ kurly.secretMount('zot-htpasswd', '/secrets')
```

## Unauthenticated until you say otherwise

With no `config` of your own this registry accepts anonymous pulls **and pushes**,
over plaintext. Keep it inside the cluster (`zot-oci-registry:5000`), or configure
authentication and put TLS in front before exposing it.

The probes ask `/v2/`, which answers `200` only while no authentication is
configured. Once it is, switch them to a connection probe — a probe reading the
`401` a correctly secured registry returns restarts the pod forever.

## The CVE scanner is off by default

The image's own configuration enables it. It then downloads and holds a
vulnerability database: hundreds of megabytes on the volume and well past the
memory this workload requests. Set `cve=true` **and** raise the resource limits, or
leave it off and scan images where you build them.

## Persistence

One OCI layout on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled). Two zot processes writing one layout is not something either of
them arbitrates. For a scaled registry, point `config.storage` at the S3 driver
instead.

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
metadata: { name: kurly, namespace: zot-oci-registry }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-zot-oci-registry, namespace: zot-oci-registry }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/zot-oci-registry, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: zot-oci-registry }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-zot-oci-registry, namespace: zot-oci-registry }
spec: { sourceRef: { kind: OCIRepository, name: kurly-zot-oci-registry } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: zot-oci-registry, namespace: zot-oci-registry }
spec:
  serviceAccountName: zot-oci-registry-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/zot-oci-registry/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-zot-oci-registry, importPath: github.com/metio/kurly/workloads/zot-oci-registry }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: zot-oci-registry, namespace: zot-oci-registry }
spec:
  serviceAccountName: zot-oci-registry-deployer
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
        name: zot-oci-registry
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: zot-oci-registry }
```

<!-- END generated: jaas-deploy -->
