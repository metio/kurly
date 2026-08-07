<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wikidocs

[Wiki|Docs](https://github.com/Zavy86/WikiDocs) — a flat-file Markdown wiki
engine that needs no database. A plain composable `kurly.http` workload; the
whole state lives in `datasets/` on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wikidocs = import 'github.com/metio/kurly/workloads/wikidocs/server.libsonnet';

kurly.list(wikidocs())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wikidocs` | |
| `image` | `zavy86/wikidocs:1.0.93` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/www/localhost/htdocs/datasets` |
| `env` / `resources` / `labels` / `annotations` | | |

## Finish the setup wizard before you publish it

Without `datasets/config.inc.php` the instance answers with `setup.php`, and
whoever reaches it first names the wiki and picks the **edit code** that
authorises every later edit. Run the wizard yourself before anyone else can reach
the instance, or put an authenticating proxy in front. Nothing in this workload
can decide that for you.

## Persistence

`datasets/` is the entire state: the documents, their revisions, the trash, the
uploaded attachments and the configuration the wizard writes. `/datasets` in the
image is a symlink into it, so the volume goes on the real path inside the
document root.

The image ships that directory with `documents/` and `trash/` already in it, and
a PersistentVolume arrives empty and hides them. An init container mounts the
same volume elsewhere — where the image's copy is still visible — and copies it
across. The marker check makes it a first-boot seed, so a configured wiki's pages
are never overwritten by the image's originals.

One flat-file tree on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled): two pods writing the same page is not something a
flat-file store resolves afterwards.

## Less hardened, deliberately

The entrypoint renumbers the `apache` account to `PUID`/`PGID`, chowns the whole
document root and then starts `httpd`, which binds `:80` and drops its workers to
`apache` — all of it from root. The root filesystem is writable because Apache
keeps its pid, locks and logs inside the image's own tree and PHP its sessions
under `/tmp`.

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
metadata: { name: kurly, namespace: wikidocs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wikidocs, namespace: wikidocs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wikidocs, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wikidocs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wikidocs, namespace: wikidocs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wikidocs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wikidocs, namespace: wikidocs }
spec:
  serviceAccountName: wikidocs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wikidocs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wikidocs, importPath: github.com/metio/kurly/workloads/wikidocs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wikidocs, namespace: wikidocs }
spec:
  serviceAccountName: wikidocs-deployer
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
        name: wikidocs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wikidocs }
```

<!-- END generated: jaas-deploy -->
