<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cyberchef

[CyberChef](https://github.com/gchq/CyberChef) — GCHQ's "cyber Swiss-army knife": a web app for encoding, encryption, compression and data analysis, all in the browser. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cyberchef = import 'github.com/metio/kurly/workloads/cyberchef/server.libsonnet';
kurly.list(cyberchef())
```

Serves on `:8000`.
