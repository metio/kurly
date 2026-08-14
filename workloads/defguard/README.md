<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# defguard

[defguard](https://github.com/DefGuard/defguard) — identity and access management built
around WireGuard. It holds the user accounts, the MFA enrolment, an OpenID Connect
provider, and the peer configuration that its gateways enforce.

This carries **core**, the control plane: a plain composable `kurly.http` workload backed
by an external PostgreSQL, holding no state of its own.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local defguard = import 'github.com/metio/kurly/workloads/defguard/core.libsonnet';

kurly.list(
  defguard(url='https://vpn.example.com')
  + kurly.expose.gateway('vpn.example.com', parent='public')
)
```

## Core is not the VPN

Core hands each gateway its peer list; the gateway that actually carries WireGuard
traffic needs `NET_ADMIN` and the node's own network, and is a separate deployment
decision from this one. Running core alone gives you the directory and the admin
interface with no tunnel behind them.

## Secure cookies and plain HTTP

The application marks its session cookies `Secure`, so a browser reaching it over `http://`
discards them and the login never completes. `cookieInsecure` relaxes that for a
deployment terminating TLS somewhere the application cannot see. It is the wrong answer
for anything on a network you do not fully control.

## Licence

The core is AGPL-3.0. Enterprise features live in the same repository under a separate
licence, and the published image is one build — which of the two applies depends on which
features are switched on.

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
metadata: { name: kurly, namespace: defguard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-defguard, namespace: defguard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/defguard, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: defguard }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-defguard, namespace: defguard }
spec: { sourceRef: { kind: OCIRepository, name: kurly-defguard } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: defguard, namespace: defguard }
spec:
  serviceAccountName: defguard-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local core = import 'github.com/metio/kurly/workloads/defguard/core.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(core())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-defguard, importPath: github.com/metio/kurly/workloads/defguard }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: defguard, namespace: defguard }
spec:
  serviceAccountName: defguard-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: core
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: defguard
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: defguard }
```

<!-- END generated: jaas-deploy -->
