<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# yacy

[YaCy](https://yacy.net/) — a peer-to-peer web search engine. It crawls and
indexes on its own and, unless you tell it otherwise, joins the public network of
peers and answers their queries as well as yours. A plain composable `kurly.http`
workload; the crawler queues, the Solr index and the peer's identity live in one
`DATA` directory on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local yacy = import 'github.com/metio/kurly/workloads/yacy/server.libsonnet';

kurly.list(yacy())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `yacy` | |
| `image` | `yacy/yacy_search_server:latest` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/opt/yacy_search_server/DATA` |
| `env` / `resources` / `labels` / `annotations` | | |

## Set the administrator password before you expose it

YaCy ships an `admin` account with **an empty password**, and its only protection
is a restriction to local access — which in a pod means anything that can reach
the container. Log in, set the password from `/ConfigAccounts_p.html`, and only
then compose an exposure. Nothing in this workload can decide it for you.

The same page decides whether the peer runs in **junior/senior** mode on the
public network or stays private to your intranet. That is a choice about what you
publish, so it is left where the software makes it, not baked into a default here.

## Storage

One index directory on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled): two JVMs writing one Solr index corrupt it. The index
grows with everything you crawl and does not shrink, so `20Gi` is a starting
point rather than a size.

## Startup

A JVM unpacking its cores on a fresh volume takes minutes, so the workload carries
a startup probe with a ten-minute budget instead of a liveness probe that stays
lenient forever. The readiness probe asks for the search page; liveness only asks
whether the port answers, because a busy crawler can be slow to render a page
while being perfectly alive.

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
metadata: { name: kurly, namespace: yacy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-yacy, namespace: yacy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/yacy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: yacy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-yacy, namespace: yacy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-yacy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: yacy, namespace: yacy }
spec:
  serviceAccountName: yacy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/yacy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-yacy, importPath: github.com/metio/kurly/workloads/yacy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: yacy, namespace: yacy }
spec:
  serviceAccountName: yacy-deployer
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
        name: yacy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: yacy }
```

<!-- END generated: jaas-deploy -->
