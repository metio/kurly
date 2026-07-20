<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docker-registry-ui

[Docker Registry UI](https://github.com/Joxit/docker-registry-ui) — a clean, self-hosted web interface for browsing a Docker/OCI registry. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ui = import 'github.com/metio/kurly/workloads/docker-registry-ui/server.libsonnet';
kurly.list(ui(registryUrl='https://registry.example.com'))
```

Point it at your registry through `registryUrl`. Serves on `:80`.
