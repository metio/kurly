<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# chatpad

[Chatpad AI](https://github.com/deiucanta/chatpad) — a self-hosted, clean web UI for OpenAI's chat models. A `kurly.http` workload on the official image. Conversations and the API key are stored client-side, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local chatpad = import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet';
kurly.list(chatpad())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:80`. The browser talks to OpenAI directly with the user's own key.
