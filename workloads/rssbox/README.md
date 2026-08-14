<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rssbox

[RSS Box](https://github.com/stefansundin/rssbox) — turns sites that stopped publishing
feeds back into RSS. YouTube channels, Twitch streams, SoundCloud, Vimeo, Instagram and a
dozen more, each as a feed any reader can subscribe to.

A plain composable `kurly.http` workload holding no state.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rssbox = import 'github.com/metio/kurly/workloads/rssbox/server.libsonnet';

kurly.list(
  rssbox(secretName='rssbox')
  + kurly.expose.gateway('rss.example.com', 'public')
)
```

## The API keys are yours, not the application's

YouTube, Vimeo, SoundCloud, Twitch and Imgur each want a credential registered in your
name; Instagram, Mixcloud, Speedrun and Dailymotion need none. A missing key does not stop
the server — the feeds for that service fail and the rest keep working — so it can be
deployed with no Secret at all and grown as credentials are obtained.

## It calls other people's APIs on your quota

Every feed a reader polls is a request to somebody else's service. A cluster with a
default-deny egress policy gives this nothing to convert, and an instance left open to the
internet spends your quota for whoever finds it.

## Redis

Optional, and only for URL resolution. Everything else works without one.

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
metadata: { name: kurly, namespace: rssbox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-rssbox, namespace: rssbox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/rssbox, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: rssbox }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-rssbox, namespace: rssbox }
spec: { sourceRef: { kind: OCIRepository, name: kurly-rssbox } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: rssbox, namespace: rssbox }
spec:
  serviceAccountName: rssbox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/rssbox/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-rssbox, importPath: github.com/metio/kurly/workloads/rssbox }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: rssbox, namespace: rssbox }
spec:
  serviceAccountName: rssbox-deployer
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
        name: rssbox
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: rssbox }
```

<!-- END generated: jaas-deploy -->
