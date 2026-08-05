<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matchering

[Matchering](https://github.com/sergree/matchering) — audio mastering by
reference. Upload a track and a reference you want it to sound like, and it
matches the loudness, frequency balance and stereo width. A plain composable
`kurly.http` workload; uploads and rendered results live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local matchering = import 'github.com/metio/kurly/workloads/matchering/server.libsonnet';

kurly.list(matchering())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `matchering` | |
| `image` | `sergree/matchering-web:0.1.7` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/data` |
| `secretName` | `matchering` | provides `secret_key` |
| `resources` | 500m–2 CPU | see below |

## The Secret is one file, and it matters more than it looks

`settings.py` reads Django's `SECRET_KEY` from `./.secret_key` — a file beside the
code — and from nowhere else. There is no environment override. The entrypoint
generates one when that file is absent.

On an ephemeral filesystem that means **a new key on every restart**, which does
not fail: it silently invalidates every session and anything else Django signed. So
the Secret's `secret_key` entry is mounted as that single file:

```jsonnet
+ kurly.secretMount(secretName, '/app/.secret_key', subPath='secret_key')
```

The entrypoint then finds the file present and leaves it alone.

```shell
kubectl create secret generic matchering \
  --from-literal=secret_key="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Root is required here

`supervisord` is configured to drop privileges to its own account and refuses to
start when it is already unprivileged:

```text
Error: Can't drop privilege as nonroot user
```

So this runs as root by necessity rather than by the image's default, with the
capabilities and escalation the drop itself needs.

## The CPU limit is doing a job

Mastering saturates whatever it is given for the length of the track. The 2-core
ceiling is what stops one upload starving everything else on the node — raise it
for the concurrency you expect rather than removing it.

## Persistence

Uploads and rendered results on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: matchering }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-matchering, namespace: matchering }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/matchering, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: matchering }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-matchering, namespace: matchering }
spec: { sourceRef: { kind: OCIRepository, name: kurly-matchering } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: matchering, namespace: matchering }
spec:
  serviceAccountName: matchering-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/matchering/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-matchering, importPath: github.com/metio/kurly/workloads/matchering }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: matchering, namespace: matchering }
spec:
  serviceAccountName: matchering-deployer
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
        name: matchering
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: matchering }
```

<!-- END generated: jaas-deploy -->
