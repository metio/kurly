<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# stash

[Stash](https://github.com/stashapp/stash) — an organiser and player for a
personal video library: it indexes the files you point it at, scrapes metadata
for them and serves a web player over the result. A plain composable
`kurly.http` workload keeping its SQLite database, configuration and generated
artefacts on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local stash = import 'github.com/metio/kurly/workloads/stash/server.libsonnet';

kurly.list(stash())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `stash` | |
| `image` | `docker.io/stashapp/stash:v0.31.1` | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | `/data` |
| `env` / `resources` / `labels` / `annotations` | | |

## Every path is an environment variable, which is why it runs unprivileged

The image defaults `STASH_CONFIG_FILE` to `/root/.stash/config.yml` and derives
the rest of its trees from there, so out of the box it expects to be root with a
writable home. Each of those paths is its own variable, so this stage points them
all at the volume — `/data/config.yml`, `/data/media`, `/data/generated`,
`/data/metadata`, `/data/cache`, `/data/blobs` — and runs as UID 1000 with the
hardened default posture intact.

## Where the media goes

`/data/media` is what Stash scans, and it is a directory of the workload's own
volume — so a library that already lives elsewhere is either copied in or the
whole volume is sized to hold it (`storageSize` defaults to `100Gi` for that
reason). Point `env.STASH_STASH` somewhere else if you mount the library
yourself.

An empty directory is not an error: the scan finds nothing and the UI stays
empty.

## Probes ask for a connection

A fresh server answers `/` with its setup wizard and a configured one redirects
to a login, so both probes are connection probes — the answer must not depend on
how far through setup somebody happens to be.

## Scanning is the expensive part

Scanning, transcoding and metadata scraping are what this workload spends its
time on, and scraping reaches out to the internet. The requests carry an idle
server; a library scan wants considerably more, and a NetworkPolicy that allows
no egress leaves every scraper silently empty-handed.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: stash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-stash, namespace: stash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/stash, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: stash }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-stash, namespace: stash }
spec: { sourceRef: { kind: OCIRepository, name: kurly-stash } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: stash, namespace: stash }
spec:
  serviceAccountName: stash-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/stash/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-stash, importPath: github.com/metio/kurly/workloads/stash }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: stash, namespace: stash }
spec:
  serviceAccountName: stash-deployer
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
        name: stash
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: stash }
```

<!-- END generated: jaas-deploy -->
