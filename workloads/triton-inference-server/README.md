<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# triton-inference-server

[NVIDIA Triton Inference Server](https://github.com/triton-inference-server/server) —
serves models from a directory of them over HTTP and gRPC, with backends for TensorRT,
ONNX, PyTorch, TensorFlow and Python.

A plain composable `kurly.http` workload. The model repository lives on one volume, which
makes this a **single writer** by default: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local triton = import 'github.com/metio/kurly/workloads/triton-inference-server/server.libsonnet';

kurly.list(
  triton(gpus=1)
  + kurly.expose.gateway('inference.example.com', 'internal')
)
```

## An empty model repository is fatal, so this starts empty on purpose

Triton loads every model under `--model-repository` at start and exits when it can load
none — which is exactly what a freshly provisioned volume gives it. The stage therefore
renders `--model-control-mode=explicit`: the server comes up holding nothing, and models
are loaded through its API once they are on the volume. `poll` and `none` both load at
start, and `none` is the mode that exits.

## GPUs are optional, the CUDA image is not

`gpus=0` requests no device and serves on the CPU, which is real for the ONNX and Python
backends and slow for everything else. Either way the image is CUDA-based, so a CPU-only
deployment still pulls eight gigabytes and runs NVIDIA's entrypoint.

## Sharing one repository

A `ReadWriteMany` volume lets several servers serve the same models — the shape to reach
for when one pod is not enough traffic, since each replica otherwise wants its own copy.

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
metadata: { name: kurly, namespace: triton-inference-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-triton-inference-server, namespace: triton-inference-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/triton-inference-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: triton-inference-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-triton-inference-server, namespace: triton-inference-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-triton-inference-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: triton-inference-server, namespace: triton-inference-server }
spec:
  serviceAccountName: triton-inference-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/triton-inference-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-triton-inference-server, importPath: github.com/metio/kurly/workloads/triton-inference-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: triton-inference-server, namespace: triton-inference-server }
spec:
  serviceAccountName: triton-inference-server-deployer
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
        name: triton-inference-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: triton-inference-server }
```

<!-- END generated: jaas-deploy -->
