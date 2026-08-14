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
  + kurly.expose.gateway('inference.example.com', parent='internal')
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
