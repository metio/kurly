<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# open-webui

[Open WebUI](https://github.com/open-webui/open-webui) — a feature-rich, self-hosted web interface for chatting with local and remote LLMs (Ollama and any OpenAI-compatible API). A `kurly.http` workload on the official image; with the default SQLite backend its database and uploads on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openWebui = import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet';
kurly.list(openWebui(ollamaBaseUrl='http://ollama:11434'))
```

Set `WEBUI_SECRET_KEY` from a Secret via `envFrom`; kurly authors **no Secret**. Point it at an external PostgreSQL (`DATABASE_URL`) to scale past SQLite. Data at `/app/backend/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.
