<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# metamcp

[MetaMCP](https://github.com/metatool-ai/metamcp) — an MCP proxy. It aggregates several
Model Context Protocol servers into one endpoint, groups them into namespaces, and applies
middleware in front, so a client holds one URL instead of a list that changes every time
a server is added.

A plain composable `kurly.http` workload backed by an external PostgreSQL, holding no
state of its own.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local metamcp = import 'github.com/metio/kurly/workloads/metamcp/server.libsonnet';

kurly.list(
  metamcp(appUrl='https://mcp.example.com', bootstrapEmail='admin@example.com')
  + kurly.expose.gateway('mcp.example.com', parent='public')
)
```

## `appUrl` is not decoration

The application builds its callback URLs from it and validates request origins against
it. Wrong or missing, you get a page that loads and a login that fails — set it to the URL
a browser actually uses.

## Bootstrap an administrator or the first visitor becomes one

Registration is open until an administrator exists. `bootstrapEmail`, with
`BOOTSTRAP_USER_PASSWORD` in the Secret, creates that account at start instead. On
anything reachable from outside, that is the difference between an instance you own and an
instance whoever found it owns.

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
metadata: { name: kurly, namespace: metamcp }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-metamcp, namespace: metamcp }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/metamcp, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: metamcp }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-metamcp, namespace: metamcp }
spec: { sourceRef: { kind: OCIRepository, name: kurly-metamcp } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: metamcp, namespace: metamcp }
spec:
  serviceAccountName: metamcp-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/metamcp/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-metamcp, importPath: github.com/metio/kurly/workloads/metamcp }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: metamcp, namespace: metamcp }
spec:
  serviceAccountName: metamcp-deployer
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
        name: metamcp
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: metamcp }
```

<!-- END generated: jaas-deploy -->
