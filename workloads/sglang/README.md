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
  + kurly.expose.gateway('llm.example.com', parent='internal')
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
