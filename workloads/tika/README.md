<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tika

[Apache Tika](https://tika.apache.org) — a content-analysis toolkit that detects and extracts text and metadata from over a thousand file types. A **stateless** `kurly.http` workload on the official image. The text-extraction companion apps like [paperless-ngx](../paperless-ngx/) expect.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tika = import 'github.com/metio/kurly/workloads/tika/server.libsonnet';
kurly.list(tika())
```

Serves on `:9998`.
