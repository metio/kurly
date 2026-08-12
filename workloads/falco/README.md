<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# falco

[Falco](https://falco.org) — runtime security: it watches the system calls every
container on a node makes and raises an alert when one matches a rule (a shell in
a container, a write to `/etc`, an unexpected outbound connection). A composable
`kurly.daemon` workload, because the thing it watches is the node.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local falco = import 'github.com/metio/kurly/workloads/falco/agent.libsonnet';

kurly.list(falco(namespace='falco'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `falco` | |
| `image` | the pinned upstream image | |
| `namespace` | `falco` | where the ServiceAccount lives — required |
| `config` | `{}` | merged over the rendered `falco.yaml` |
| `rules` | `{}` | extra rule files, keyed by file name |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

## Least privilege, not privileged

Falco is usually deployed with a fully privileged container. It does not need one
with the modern eBPF driver, which this stage uses. Four capabilities cover it:

| | |
|---|---|
| `BPF` | load the programs |
| `PERFMON` | read the perf buffers |
| `SYS_RESOURCE` | raise the locked-memory limit |
| `SYS_PTRACE` | read `/proc` for process lineage |

That is the set Falco's own chart documents for its least-privileged mode, and the
rest of the hardened posture stands — including the read-only root filesystem.
Compose `kurly.privileged()` only where a node's kernel is too old for the modern
driver and the kernel module is the only option.

`/sys/kernel` is mounted for the tracefs and debugfs the driver attaches through.

## What it sees

Every syscall from every container on the node. That is the whole job, and it is
also why this is not a tenant workload: the alerts it produces describe other
people's software.

## Rules are the product

The image ships the default ruleset, which is a starting point rather than a
policy. `rules` adds files to it, and tuning them down is how a deployment stops
paging on its own normal behaviour. Output goes to stdout as JSON, where a log
pipeline can pick it up; Falco's gRPC and HTTP outputs are configured through
`config`.

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
metadata: { name: kurly, namespace: falco }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-falco, namespace: falco }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/falco, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: falco }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-falco, namespace: falco }
spec: { sourceRef: { kind: OCIRepository, name: kurly-falco } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: falco, namespace: falco }
spec:
  serviceAccountName: falco-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local agent = import 'github.com/metio/kurly/workloads/falco/agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-falco, importPath: github.com/metio/kurly/workloads/falco }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: falco, namespace: falco }
spec:
  serviceAccountName: falco-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: agent
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: falco
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: falco }
```

<!-- END generated: jaas-deploy -->
