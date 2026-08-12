<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# barcodebuddy

[Barcode Buddy](https://github.com/Forceu/barcodebuddy) — scan a barcode and have
the item added to, or consumed from, your [Grocy](../grocy/README.md) inventory. A
composable `kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local barcodebuddy = import 'github.com/metio/kurly/workloads/barcodebuddy/server.libsonnet';

kurly.list(barcodebuddy(grocyUrl='http://grocy/api', secretName='barcodebuddy'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `barcodebuddy` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | `/config` |
| `grocyUrl` | none | the Grocy API this drives |
| `secretName` | none | `BBUDDY_API_KEY` |
| `resources` / `env` / `labels` / `annotations` | | |

Serves the web interface on `:80` — compose an exposure onto it.

## It is a front end for Grocy

`grocyUrl` points at a Grocy API and `secretName` carries the API key it
authenticates with. kurly carries `grocy`, so the pair deploys together. Pointed at
nothing, Barcode Buddy starts and every scan fails.

## The scanner is somewhere else

A USB barcode reader is attached to a machine, not to a pod. The arrangements that
work in a cluster are the web interface, a phone camera, or the project's own
screen-reader script running beside the scanner and posting to this API.

The image starts nginx, php-fpm and its websocket server under supervisor as root,
so root, escalation, the runtime capabilities and a writable root filesystem are
relaxed deliberately.

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
metadata: { name: kurly, namespace: barcodebuddy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-barcodebuddy, namespace: barcodebuddy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/barcodebuddy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: barcodebuddy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-barcodebuddy, namespace: barcodebuddy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-barcodebuddy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: barcodebuddy, namespace: barcodebuddy }
spec:
  serviceAccountName: barcodebuddy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/barcodebuddy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-barcodebuddy, importPath: github.com/metio/kurly/workloads/barcodebuddy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: barcodebuddy, namespace: barcodebuddy }
spec:
  serviceAccountName: barcodebuddy-deployer
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
        name: barcodebuddy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: barcodebuddy }
```

<!-- END generated: jaas-deploy -->
