<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bunkerm

[BunkerM](https://github.com/bunkeriot/BunkerM) — an MQTT broker with a management
interface. It bundles Eclipse Mosquitto with a web dashboard for its clients, ACLs and
dynamic-security roles, so the broker is administered from a browser rather than by
editing configuration files and restarting.

A plain composable `kurly.http` workload. The broker's persistence, its password file and
the dashboard's API key live on one volume, which makes this a **single writer**: one
replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bunkerm = import 'github.com/metio/kurly/workloads/bunkerm/server.libsonnet';

kurly.list(
  bunkerm()
  + kurly.expose.gateway('mqtt-admin.example.com', 'public')
)
```

## Two ports, and only one of them is HTTP

`:2000` serves the dashboard and its API, and is the Service's `http` port. `:1900` is
the MQTT listener — a raw TCP protocol, published here as the extra port `mqtt`. It needs
a TCP route of its own: composing an HTTP exposure publishes the dashboard and leaves the
broker unreachable, and no MQTT client can speak to an HTTPRoute.

## The API key

The dashboard authenticates against a key at `/nextjs/data/.api_key`. Supplied through a
Secret as `API_KEY` it is used and persisted; left unset, the first start generates a
random one and keeps it — which means the deployment does not know it until somebody
reads it out of the volume. Set one if anything is going to drive the API.

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
metadata: { name: kurly, namespace: bunkerm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bunkerm, namespace: bunkerm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bunkerm, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bunkerm }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bunkerm, namespace: bunkerm }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bunkerm } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bunkerm, namespace: bunkerm }
spec:
  serviceAccountName: bunkerm-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bunkerm/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bunkerm, importPath: github.com/metio/kurly/workloads/bunkerm }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bunkerm, namespace: bunkerm }
spec:
  serviceAccountName: bunkerm-deployer
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
        name: bunkerm
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bunkerm }
```

<!-- END generated: jaas-deploy -->
