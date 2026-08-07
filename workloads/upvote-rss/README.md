<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# upvote-rss

[Upvote RSS](https://github.com/johnwarne/upvote-rss) — turns a subreddit, a
Hacker News front page or a Lemmy community into a full-text RSS feed, filtered by
score, so a reader shows only the posts a community actually voted up. A plain
composable `kurly.http` workload; the response cache lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local upvoteRss = import 'github.com/metio/kurly/workloads/upvote-rss/server.libsonnet';

kurly.list(upvoteRss())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `upvote-rss` | |
| `image` | `ghcr.io/johnwarne/upvote-rss:v1.8.1` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/app/cache` |
| `secretName` | none | Reddit client id/secret, summariser API keys — all optional |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the feed builder and the feeds themselves on `:80`; compose an exposure
onto it.

## It fetches from the internet, and from anywhere else it can reach

Every article it summarises is fetched from the site that published it, so the pod
needs egress. A NetworkPolicy composed onto it that forgets this leaves the feeds
empty.

There is also **no authentication**. Anyone who reaches it can ask it to fetch a
URL, which makes it a fetcher on whatever network the pod sits on. Keep it
in-cluster, or put an authenticating proxy in front and restrict its egress.

## Credentials are optional

Without `secretName` Reddit is read anonymously — which works, and is rate limited
harder — and articles are not summarised. Supply Reddit's `REDDIT_USER`,
`REDDIT_CLIENT_ID` and `REDDIT_CLIENT_SECRET`, and an API key for whichever
summarisation service you configure, in that Secret.

## Less hardened, deliberately

The entrypoint chowns `/app` and `/data` and then drops to the `upvote-rss`
account with `su-exec`, which it can only do starting from root — so this runs
`rootUser` with privilege escalation allowed and capabilities kept. The root
filesystem is writable too, because the image ships no such account: the
entrypoint creates the group and the user at every start, and on a read-only root
filesystem those writes fail without stopping the script, leaving the container to
die on `su-exec: getpwnam(upvote-rss)`.

`enableServiceLinks` is off. PHP publishes the process environment as `$_SERVER`,
and the application reads `REDIS_HOST` and `REDIS_PORT` from there — a Service
named `redis` in the same namespace would otherwise configure this workload's
cache backend by accident.

## Persistence

One filesystem cache on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). The cache is not precious — losing it costs a slow
first request per feed — but two pods writing the same directory is not something
the application arbitrates.

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
metadata: { name: kurly, namespace: upvote-rss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-upvote-rss, namespace: upvote-rss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/upvote-rss, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: upvote-rss }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-upvote-rss, namespace: upvote-rss }
spec: { sourceRef: { kind: OCIRepository, name: kurly-upvote-rss } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: upvote-rss, namespace: upvote-rss }
spec:
  serviceAccountName: upvote-rss-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/upvote-rss/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-upvote-rss, importPath: github.com/metio/kurly/workloads/upvote-rss }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: upvote-rss, namespace: upvote-rss }
spec:
  serviceAccountName: upvote-rss-deployer
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
        name: upvote-rss
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: upvote-rss }
```

<!-- END generated: jaas-deploy -->
