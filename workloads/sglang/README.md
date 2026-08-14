<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sglang

[SGLang](https://github.com/sgl-project/sglang) — a serving runtime for large language
models. It loads one model onto the GPUs of the node it lands on and answers an
OpenAI-compatible API in front of it.

A plain composable `kurly.http` workload. The model cache lives on one volume, which
makes it a **single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sglang = import 'github.com/metio/kurly/workloads/sglang/server.libsonnet';

kurly.list(
  sglang(model='meta-llama/Llama-3.1-8B-Instruct', gpus=1)
  + kurly.expose.gateway('llm.example.com', 'internal')
)
```

## It does not run without an NVIDIA GPU

The image is built on CUDA and its entrypoint is NVIDIA's. `gpus` becomes an
`nvidia.com/gpu` request and limit, so a node without the device plugin leaves the pod
Pending rather than starting it slowly. There is no CPU fallback worth offering: a model
that fits in system memory still answers at a speed nobody would put in front of users.

## The model download

`model` names a Hugging Face repository the server fetches at boot — tens of gigabytes for
a mid-sized model. `HF_HOME` points at the volume so the download survives a restart; a
pod without one fetches it all again on every cold start. A gated repository needs
`HF_TOKEN` from a Secret, and the server exits when the download is refused.

## Scaling

More traffic means more of these, each with its own cache, behind something that spreads
requests. One pod owns its GPUs for as long as it runs.

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
metadata: { name: kurly, namespace: sglang }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sglang, namespace: sglang }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sglang, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sglang }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sglang, namespace: sglang }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sglang } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sglang, namespace: sglang }
spec:
  serviceAccountName: sglang-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sglang/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sglang, importPath: github.com/metio/kurly/workloads/sglang }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sglang, namespace: sglang }
spec:
  serviceAccountName: sglang-deployer
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
        name: sglang
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sglang }
```

<!-- END generated: jaas-deploy -->
