<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# xbackbone

[XBackBone](https://github.com/SergiX44/XBackBone) — a lightweight file and screenshot
host with ShareX support. A plain composable `kurly.http` workload on the maintained
[LinuxServer](https://docs.linuxserver.io/images/docker-xbackbone/) image, with
uploads, the SQLite database and the generated configuration on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local xbackbone = import 'github.com/metio/kurly/workloads/xbackbone/server.libsonnet';

kurly.list(xbackbone())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `xbackbone` | |
| `image` | `lscr.io/linuxserver/xbackbone:3.8.2-ls235` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | uploads, database and config (`/config`) |
| `puid` / `pgid` | `1000` / `1000` | own the mounted files |
| `timezone` | `UTC` | `TZ` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Storage

XBackBone stores uploads, its SQLite database and its generated configuration under
`/config`, so it needs **no external database**. The volume is ReadWriteOnce and holds
the uploads, so this is **one replica, recreated** — never rolled, to keep two pods off
the files. Point it at a MySQL server through the first-run installer if you would
rather keep the metadata elsewhere; the uploads stay on the volume either way.

## Security

The LinuxServer image runs its s6-overlay init as **root** and drops to the
`puid`/`pgid` user, so this workload relaxes kurly's non-root and read-only-rootfs
defaults while keeping the rest of the hardening — dropped capabilities (a named set
granted back), seccomp, no privilege escalation and resource limits.

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
metadata: { name: kurly, namespace: xbackbone }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-xbackbone, namespace: xbackbone }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/xbackbone, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: xbackbone }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-xbackbone, namespace: xbackbone }
spec: { sourceRef: { kind: OCIRepository, name: kurly-xbackbone } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: xbackbone, namespace: xbackbone }
spec:
  serviceAccountName: xbackbone-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/xbackbone/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-xbackbone, importPath: github.com/metio/kurly/workloads/xbackbone }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: xbackbone, namespace: xbackbone }
spec:
  serviceAccountName: xbackbone-deployer
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
        name: xbackbone
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: xbackbone }
```

<!-- END generated: jaas-deploy -->
