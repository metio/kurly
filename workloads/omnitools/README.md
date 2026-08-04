<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# omnitools

[OmniTools](https://github.com/iib0011/omni-tools) — a self-hosted collection of
everyday utilities: image and video conversion, PDF tools, text and JSON
formatting, encoders and generators. A plain composable `kurly.http` workload, and
about as small as one gets here: nginx serving a static bundle, no database, no
volume, no Secret.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local omnitools = import 'github.com/metio/kurly/workloads/omnitools/server.libsonnet';

kurly.list(omnitools())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `omnitools` | |
| `image` | `iib0011/omni-tools:0.6.0` | |
| `replicas` | `1` | a plain knob — there is no state to share |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:80`:

```jsonnet
kurly.list([
  omnitools()
  + kurly.expose.ownGateway('tools.example.com', 'istio', tls='omnitools-tls'),
  kurly.certificate('omnitools-tls', ['tools.example.com'], 'letsencrypt-prod'),
])
```

## It holds no data, at any point

Every tool runs **in the browser**. Files are processed client-side and never
uploaded, so this workload stores nothing about anybody: there is nothing to back
up, nothing to leak, and no reason not to scale it out or run it on spot capacity.
That is a property of the software rather than a default chosen here — which is
why `replicas` is an ordinary parameter, where most workloads in this catalogue
are pinned to one by a volume they cannot share.

## One capability instead of root

The image's nginx listens on `:80`, and an unprivileged process may not bind a
port below 1024. Rather than run the whole server as root to obtain that one port,
this names the `nginx` account the image already builds (uid 101) and grants back
exactly the capability binding needs:

```jsonnet
+ kurly.runAs(101, gid=101)
+ kurly.addCapabilities(['NET_BIND_SERVICE'])
```

Everything else stays dropped. nginx's pid, temporary bodies and caches are
ephemeral scratch, not volumes.

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
metadata: { name: kurly, namespace: omnitools }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-omnitools, namespace: omnitools }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/omnitools, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: omnitools }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-omnitools, namespace: omnitools }
spec: { sourceRef: { kind: OCIRepository, name: kurly-omnitools } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: omnitools, namespace: omnitools }
spec:
  serviceAccountName: omnitools-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/omnitools/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-omnitools, importPath: github.com/metio/kurly/workloads/omnitools }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: omnitools, namespace: omnitools }
spec:
  serviceAccountName: omnitools-deployer
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
        name: omnitools
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: omnitools }
```

<!-- END generated: jaas-deploy -->
