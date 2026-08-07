<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# llmkube

[LLMKube](https://llmkube.com/) — a Kubernetes operator for self-hosted
language-model inference. It watches `Model`, `InferenceService` and
`ModelRouter` custom resources and creates the Deployments, Services,
PersistentVolumeClaims and download jobs that fetch model weights and serve an
OpenAI-compatible API, placing the serving pods on whatever accelerators the
nodes offer.

This workload is the **controller manager itself**, not one of the resources it
reconciles — the counterpart to [ollama](../ollama/), which serves models
directly instead of managing them. A plain composable `kurly.http` workload, but
one that needs **cluster** access to reconcile its custom resources in every
namespace, so it carries a ServiceAccount + ClusterRole + ClusterRoleBinding
alongside the namespaced leader-election Role + RoleBinding.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local llmkube = import 'github.com/metio/kurly/workloads/llmkube/controller.libsonnet';

kurly.list(llmkube(namespace='llmkube-system'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `llmkube` | |
| `namespace` | `llmkube-system` | **must match where you deploy** — see below |
| `image` | the pinned `llmkube-controller` | |
| `replicas` | `1` | |
| `leaderElect` | `true` | keeps a second replica idle instead of reconciling twice |
| `resources` | `10m` CPU / `512Mi`–`2Gi` | |
| `env` / `labels` / `annotations` / `podLabels` / `podAnnotations` | | |

## The CRDs come first

kurly ships no CRDs: they are large, they version with the operator, and a stale
copy is worse than none. Apply the custom resource definitions of the release the
pinned image belongs to **before** this workload — controller-runtime establishes
its watches at start-up, so a manager whose kinds are missing exits before it is
ever ready, and the Deployment never rolls out.

## Why `namespace` is required

The controller reconciles its resources across **every** namespace, so it needs a
`ClusterRole` + `ClusterRoleBinding` rather than the namespaced Role the `http`
kind mints on its own. A `ClusterRoleBinding` names its `ServiceAccount` subject
by namespace, and a cluster-scoped object cannot be namespace-stamped by the
consumer later — so the namespace has to be known at render, and it must match
where you actually deploy. (Same reason [opencost](../opencost/) and
[metrics-server](../metrics-server/) take one.)

## Ports, storage and posture

Protected metrics on `:8443` — the endpoint authenticates and authorizes each
scrape against the API server, which is why the ClusterRole may create
`TokenReview`s and `SubjectAccessReview`s. Health and readiness are on `:8081`
and stay off the Service.

The controller keeps the hardened default posture: non-root at `65532`, a
read-only root filesystem, all capabilities dropped. Two per-pod scratch volumes
make that hold — `/tmp` for the self-signed metrics serving certificate, and
`/models` for staging a locally sourced weight file while it is validated. The
model cache that inference pods read is a PersistentVolumeClaim the controller
provisions at reconcile time, so nothing here pins the manager to a node.

The serving pods the operator creates are **its** manifests, not kurly's: their
images, resources and GPU requests come from the custom resources you write, and
they are outside everything kurly derives about this workload.

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
metadata: { name: kurly, namespace: llmkube }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-llmkube, namespace: llmkube }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/llmkube, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: llmkube }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-llmkube, namespace: llmkube }
spec: { sourceRef: { kind: OCIRepository, name: kurly-llmkube } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: llmkube, namespace: llmkube }
spec:
  serviceAccountName: llmkube-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local controller = import 'github.com/metio/kurly/workloads/llmkube/controller.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(controller())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-llmkube, importPath: github.com/metio/kurly/workloads/llmkube }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: llmkube, namespace: llmkube }
spec:
  serviceAccountName: llmkube-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: controller
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: llmkube
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: llmkube }
```

<!-- END generated: jaas-deploy -->
