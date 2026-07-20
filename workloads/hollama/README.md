<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hollama

[Hollama](https://github.com/fmaclen/hollama) — a minimal, self-hosted web UI for Ollama and OpenAI-compatible LLMs. A `kurly.http` workload on the official image. Sessions and settings are stored client-side, so the server holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hollama = import 'github.com/metio/kurly/workloads/hollama/server.libsonnet';
kurly.list(hollama())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:4173`. The browser talks to your Ollama / OpenAI endpoint directly; configure it in the UI.
