<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# isso

[Isso](https://github.com/isso-comments/isso) — a small comment server for static
sites. A script tag on the page, comments in SQLite, no accounts and no third
party. A plain composable `kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local isso = import 'github.com/metio/kurly/workloads/isso/server.libsonnet';

kurly.list(isso(host='https://example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `isso` | |
| `image` | `ghcr.io/isso-comments/isso:0.14.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/db` |
| `host` | **required** | the site allowed to embed the widget |
| `config` | a starter `isso.cfg` | replaces it wholesale |
| `env` / `resources` / `labels` / `annotations` | | |

```jsonnet
kurly.list([
  isso(host='https://example.com')
  + kurly.expose.ownGateway('comments.example.com', 'istio', tls='isso-tls'),
  kurly.certificate('isso-tls', ['comments.example.com'], 'letsencrypt-prod'),
])
```

## `host` is required and cannot be guessed

Isso serves comments only for pages under the origins named in `host` and rejects
requests from anywhere else. A wrong value gives the worst kind of failure: the
widget loads, the page looks fine, and every attempt to comment is refused.

## The starter configuration

`config` replaces `isso.cfg` wholesale, and it mounts as a **single file**, so the
rest of `/config` is left alone. The default turns on Isso's guard — rate limiting,
no self-replies, an author required — because a comment box reachable from the
internet with none of that is a spam target within days.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the file.

## A note on `HOME`

The image never selects a user account, so this workload names one — and gunicorn
then puts its control-server socket in `$HOME/.gunicorn`, where `HOME` resolves to
`/` for a uid with no home directory. On a read-only root filesystem that fails.

The failure is worth knowing about because it is nearly invisible: Isso still
serves, the probes still pass, and the only symptom is one `ERROR` line at startup
repeating in the logs of a workload that is otherwise working. `HOME` is therefore
set to `/tmp`.

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
metadata: { name: kurly, namespace: isso }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-isso, namespace: isso }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/isso, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: isso }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-isso, namespace: isso }
spec: { sourceRef: { kind: OCIRepository, name: kurly-isso } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: isso, namespace: isso }
spec:
  serviceAccountName: isso-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/isso/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-isso, importPath: github.com/metio/kurly/workloads/isso }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: isso, namespace: isso }
spec:
  serviceAccountName: isso-deployer
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
        name: isso
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: isso }
```

<!-- END generated: jaas-deploy -->
