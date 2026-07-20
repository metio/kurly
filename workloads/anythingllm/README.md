<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# anythingllm

[AnythingLLM](https://anythingllm.com) — a self-hosted, all-in-one AI application: chat with your documents through RAG, agents and many LLM/embedding providers. A `kurly.http` workload on the official image; its storage (embedded vector database, uploaded documents, settings) on a PersistentVolume under `/app/server/storage`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local anythingllm = import 'github.com/metio/kurly/workloads/anythingllm/server.libsonnet';
kurly.list(anythingllm())
```

Storage at `/app/server/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3001`.

**Providers:** point it at your LLM and embedding providers with the documented environment variables. kurly authors no Secret; pass non-secret settings via `env` and provide API keys through a Secret (compose `kurly.envFromSecret` on).
