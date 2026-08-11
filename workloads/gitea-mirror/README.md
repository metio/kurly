<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gitea-mirror

[Gitea Mirror](https://github.com/RayLabsHQ/gitea-mirror) — mirrors GitHub
repositories into a Gitea (or Forgejo) instance on a schedule, with a web UI to
pick what is mirrored. A plain composable `kurly.http` workload: jobs, mirror
history and the account live in a SQLite database on a PersistentVolume, so it
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local giteaMirror = import 'github.com/metio/kurly/workloads/gitea-mirror/server.libsonnet';

kurly.list(giteaMirror(publicUrl='https://mirror.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gitea-mirror` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite database (`/app/data`) |
| `publicUrl` | none | the URL a browser reaches this at |
| `secretName` | none | a Secret holding `BETTER_AUTH_SECRET` and `ENCRYPTION_SECRET` |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:4321` — compose an exposure onto it.

## Public URL

`publicUrl` is what the session cookies and OAuth callbacks are signed against,
so it has to be the URL a browser actually reaches. A login that appears to
succeed and then bounces back to the form is this value disagreeing with the
address bar.

## Secrets

Left to itself the image mints a session key and an encryption key on first start
and keeps them in dot-files on the volume, so restarts survive and nothing has to
be authored. `secretName` takes that over for a deployment that wants those keys
backed up and rotated somewhere other than the volume. The encryption key protects
the stored forge tokens: losing it loses them.

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
metadata: { name: kurly, namespace: gitea-mirror }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gitea-mirror, namespace: gitea-mirror }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gitea-mirror, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gitea-mirror }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gitea-mirror, namespace: gitea-mirror }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gitea-mirror } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gitea-mirror, namespace: gitea-mirror }
spec:
  serviceAccountName: gitea-mirror-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gitea-mirror/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gitea-mirror, importPath: github.com/metio/kurly/workloads/gitea-mirror }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gitea-mirror, namespace: gitea-mirror }
spec:
  serviceAccountName: gitea-mirror-deployer
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
        name: gitea-mirror
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gitea-mirror }
```

<!-- END generated: jaas-deploy -->
