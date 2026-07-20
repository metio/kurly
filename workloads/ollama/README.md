<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ollama

[Ollama](https://ollama.com) — a self-hosted runtime for running large language models locally, with a simple REST API. A `kurly.http` workload on the official image; downloaded models on a PersistentVolume. The backend [open-webui](../open-webui/) and many AI apps talk to.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ollama = import 'github.com/metio/kurly/workloads/ollama/server.libsonnet';
kurly.list(ollama())
```

Runs on CPU by default; for GPU acceleration schedule it on a GPU node and request the device resource. Models at `/models` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:11434`.
