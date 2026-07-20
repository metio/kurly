<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mermaid-live-editor

[Mermaid Live Editor](https://github.com/mermaid-js/mermaid-live-editor) — a self-hosted, in-browser editor for Mermaid diagrams (flowcharts, sequence diagrams, Gantt charts and more from text). A `kurly.http` workload on the official image. Diagrams are rendered client-side and shared via URL, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mermaid = import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet';
kurly.list(mermaid())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:8080`.
