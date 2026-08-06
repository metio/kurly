<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tiny-tiny-rss

[Tiny Tiny RSS](https://tt-rss.org) — a web-based news feed reader and aggregator for RSS
and Atom. The official image is **PHP-FPM alone**: it listens on `:9000` and speaks FastCGI,
so it serves nothing a browser can talk to. Upstream pairs it with their own nginx image and
a feed-fetching daemon, and this workload runs all **three** processes in one pod — the FPM
app as the workload's container, **nginx and the updater as sidecars** — over a shared
working-copy volume, because that is the arrangement the software has.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ttrss = import 'github.com/metio/kurly/workloads/tiny-tiny-rss/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='tiny-tiny-rss-db', database='tinytinyrss'),
  ttrss(selfUrl='https://rss.example.com/tt-rss')
  + kurly.expose.gateway('rss.example.com', 'shared'),
])
```

The nginx sidecar serves the app on `:80` **under `/tt-rss`** — that is where the app
container installs its working copy, so it is the app's own layout rather than a choice made
here. Tiny Tiny RSS then refuses to work until `TTRSS_SELF_URL_PATH` is the URL a browser
actually reaches it at, `/tt-rss` suffix included; no default is right anywhere, so `selfUrl`
is a parameter and unset renders no variable at all.

The PostgreSQL coordinates come from `TTRSS_DB_*` and the password from `TTRSS_DB_PASS` in a
Secret via `envFrom` — kurly authors **no Secret**. The app creates the `pg_trgm` extension on
startup, so its database user must be allowed to. Plugin updates are off by default: the
startup script otherwise `git pull`s every local plugin from the internet before it listens,
which a cluster with no egress waits out on every restart.

The startup script runs as root — it creates the `app` user, chowns the working copy, rsyncs
the sources onto the volume and drops privileges with `sudo` — so this workload is
deliberately less hardened; the sidecars inherit that posture rather than restating one.
Single writer: the working copy is a ReadWriteOnce volume shared by all three containers, so
one replica, recreated (never rolled) to keep two pods off the files.

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
metadata: { name: kurly, namespace: tiny-tiny-rss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tiny-tiny-rss, namespace: tiny-tiny-rss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tiny-tiny-rss, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tiny-tiny-rss }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tiny-tiny-rss, namespace: tiny-tiny-rss }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tiny-tiny-rss } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tiny-tiny-rss, namespace: tiny-tiny-rss }
spec:
  serviceAccountName: tiny-tiny-rss-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tiny-tiny-rss/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tiny-tiny-rss, importPath: github.com/metio/kurly/workloads/tiny-tiny-rss }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tiny-tiny-rss, namespace: tiny-tiny-rss }
spec:
  serviceAccountName: tiny-tiny-rss-deployer
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
        name: tiny-tiny-rss
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tiny-tiny-rss }
```

<!-- END generated: jaas-deploy -->
