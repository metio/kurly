<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mastodon

[Mastodon](https://joinmastodon.org) — the leading self-hosted ActivityPub/Fediverse
microblogging platform. It runs as **three workloads** — a `web`/API server, a `streaming` server
for real-time timelines, and a `sidekiq` background worker — backed by an external PostgreSQL and
Redis, with media in S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local web = import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet';
local streaming = import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet';
local sidekiq = import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='mastodon-db', database='mastodon'),
  web(localDomain='social.example.com'),
  streaming(),
  sidekiq(),
])
```

`LOCAL_DOMAIN` is **baked into every `@handle` and cannot be changed** — set it deliberately. All
three stages share a Secret (`mastodon-secrets`) via `envFrom` holding the PostgreSQL/Redis
connection, `SECRET_KEY_BASE`, `OTP_SECRET`, the VAPID keys and the S3 settings — kurly authors
**no Secret**. The `web` stage serves on `:3000`, `streaming` on `:4000` (route
`/api/v1/streaming` to it), and `sidekiq` has no Service. Media goes to S3 (pair with
[seaweedfs](../seaweedfs/)), so all stages are stateless.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults. Delivered end to end through Flux, JaaS and stageset-controller on 2026-08-01, and observed rolling out.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: mastodon }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mastodon, namespace: mastodon }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mastodon, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mastodon }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mastodon, namespace: mastodon }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mastodon } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mastodon-sidekiq, namespace: mastodon }
spec:
  serviceAccountName: mastodon-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local sidekiq = import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(sidekiq())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mastodon, importPath: github.com/metio/kurly/workloads/mastodon }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mastodon-streaming, namespace: mastodon }
spec:
  serviceAccountName: mastodon-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local streaming = import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(streaming())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mastodon, importPath: github.com/metio/kurly/workloads/mastodon }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mastodon-web, namespace: mastodon }
spec:
  serviceAccountName: mastodon-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local web = import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(web())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mastodon, importPath: github.com/metio/kurly/workloads/mastodon }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mastodon, namespace: mastodon }
spec:
  serviceAccountName: mastodon-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: sidekiq
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mastodon-sidekiq
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mastodon-sidekiq }
    - name: streaming
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mastodon-streaming
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mastodon-streaming }
    - name: web
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mastodon-web
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mastodon-web }
```

<!-- END generated: jaas-deploy -->
