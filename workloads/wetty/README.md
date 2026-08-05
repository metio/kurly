<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wetty

[WeTTY](https://github.com/butlerx/wetty) — a terminal in the browser. It opens an
SSH connection to a host you name and renders it as a web page. A plain composable
`kurly.http` workload and a stateless one: it stores nothing, so it claims no
volume and `replicas` is an ordinary knob.

## Read this before exposing it

WeTTY turns an HTTP request into a shell session on `sshHost`, and it performs
**no authentication of its own**. Anyone who reaches the page gets that host's SSH
login prompt; anyone with credentials for it gets a shell.

That is not a flaw — it is what the software is — but it means the exposure is the
security boundary. Put an authenticating proxy in front of it, keep it on an
internal route, or point it at a host that is meant to be reachable that way. kurly
cannot make that judgement for you, and nothing here authenticates anybody.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wetty = import 'github.com/metio/kurly/workloads/wetty/server.libsonnet';

kurly.list(wetty(sshHost='bastion.internal'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wetty` | |
| `image` | `wettyoss/wetty:3.0.0` | |
| `sshHost` | **required** | the host to connect to |
| `sshPort` | `22` | |
| `sshUser` | unset | unset makes the visitor type their own name |
| `base` | `/wetty/` | the path it is served under |
| `replicas` | `1` | a real knob — no state to share |

`sshHost` has no default because WeTTY's own default is `localhost`, which inside
a container is the WeTTY pod itself: a terminal that connects to a machine with no
sshd and fails on every attempt.

Leaving `sshUser` unset is usually right for a shared bastion terminal — each
visitor authenticates as themselves rather than everyone sharing one account.

## Persistence

None. Nothing is stored, so there is nothing to back up and no reason not to run
several replicas.

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
metadata: { name: kurly, namespace: wetty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wetty, namespace: wetty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wetty, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wetty }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wetty, namespace: wetty }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wetty } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wetty, namespace: wetty }
spec:
  serviceAccountName: wetty-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wetty/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wetty, importPath: github.com/metio/kurly/workloads/wetty }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wetty, namespace: wetty }
spec:
  serviceAccountName: wetty-deployer
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
        name: wetty
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wetty }
```

<!-- END generated: jaas-deploy -->
