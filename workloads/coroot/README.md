<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# coroot

[Coroot](https://coroot.com) — an observability platform that builds a service map
from eBPF telemetry and turns it into answers about latency, errors and cost,
without instrumenting the applications. Two composable stages: a server and a
node-agent.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/coroot/server.libsonnet';
local agent = import 'github.com/metio/kurly/workloads/coroot/node-agent.libsonnet';

kurly.list([
  server(
    prometheusUrl='http://prometheus:9090',
    clickhouseAddress='clickhouse:9000',
    secretName='coroot',
  ),
  agent(collectorEndpoint='http://coroot:8080'),
])
```

| Parameter (server) | Default | Notes |
|---|---|---|
| `name` | `coroot` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | configuration and cache (`/data`) |
| `prometheusUrl` | none | where the metrics live |
| `clickhouseAddress` / `clickhouseUser` / `clickhouseDatabase` | none / `default` / `default` | traces, logs and profiles |
| `secretName` | none | `BOOTSTRAP_CLICKHOUSE_PASSWORD` |
| `refreshInterval` | `15s` | |
| `extraArgs` / `env` | `[]` / `{}` | |

The node-agent stage takes `port`, `collectorEndpoint` and `extraArgs`.

Serves the web app on `:8080` — compose an exposure onto it.

## The server sees nothing on its own

Every measurement comes from the node-agent, one per node, which is where the
privilege and the eBPF live. A Coroot with no agents starts, serves an empty
service map, and reports no error worth noticing. Deploy both.

## The agent is privileged, and there is no smaller version

It attaches eBPF programs that trace every container's syscalls and network
activity, shares the node's PID namespace so it can resolve a process to the
container that owns it, and reads the cgroup hierarchy to attribute what it sees.
Upstream's own manifest is privileged with `hostPID`, and this stage matches it
rather than inventing a weaker set that would silently measure less. The catalogue
reports it as `clusterScoped` and PSS-privileged so nobody deploys it by accident.

A privileged agent on every node is a large trust decision, and the honest framing
is that it is the same one every eBPF observability tool asks for. It belongs in a
namespace only cluster operators can write to. Kernel 5.1 or newer — the programs
will not load on anything older, and the agent exits rather than degrading.

## Two dependencies, different jobs

Prometheus holds the metrics and ClickHouse the traces, logs and profiles; Coroot
bootstraps its own configuration to point at both on first start. Neither is
optional in a deployment that shows anything, and kurly carries neither —
ClickHouse is not in this catalogue because its authors sell hosting for it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: coroot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-coroot, namespace: coroot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/coroot, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: coroot }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-coroot, namespace: coroot }
spec: { sourceRef: { kind: OCIRepository, name: kurly-coroot } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: coroot-node-agent, namespace: coroot }
spec:
  serviceAccountName: coroot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local node_agent = import 'github.com/metio/kurly/workloads/coroot/node-agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(node_agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-coroot, importPath: github.com/metio/kurly/workloads/coroot }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: coroot-server, namespace: coroot }
spec:
  serviceAccountName: coroot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/coroot/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-coroot, importPath: github.com/metio/kurly/workloads/coroot }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: coroot, namespace: coroot }
spec:
  serviceAccountName: coroot-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: node-agent
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: coroot-node-agent
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: coroot-node-agent }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: coroot-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: coroot-server }
```

<!-- END generated: jaas-deploy -->
