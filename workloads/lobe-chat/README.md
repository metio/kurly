<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lobe-chat

[LobeChat](https://github.com/lobehub/lobe-chat) — a self-hosted, open-source AI chat UI supporting many LLM providers, plugins and multimodal input. A `kurly.http` workload on the official image. In its default mode conversations are stored client-side, so the server holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lobechat = import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet';
kurly.list(lobechat())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:3210`.

**Providers:** point LobeChat at your LLM providers with the documented environment variables. kurly authors no Secret; pass non-secret settings via `env` and provide API keys through a Secret (compose `kurly.envFromSecret` on).
