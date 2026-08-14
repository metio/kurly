<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gpustack

[GPUStack](https://github.com/gpustack/gpustack) — a manager for a GPU cluster. It holds
the model catalogue, schedules inference onto workers, and serves an OpenAI-compatible
API in front of whatever they are running.

This carries the **server**, which needs no GPU of its own. A plain composable
`kurly.http` workload; the database and model metadata share one volume, which makes it a
**single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gpustack = import 'github.com/metio/kurly/workloads/gpustack/server.libsonnet';

kurly.list(
  gpustack()
  + kurly.expose.gateway('models.example.com', parent='public')
)
```

## The workers are not this

A worker is where a model actually runs, and upstream starts one with `--privileged`, the
host's network, the host's Docker socket and the NVIDIA runtime. That combination is a
node agent rather than a tenant's deployment, and this recipe deliberately does not
package it. Run the server here and join workers to it.

## The first start generates the credentials

The server writes an initial admin password and a worker join token under
`/var/lib/gpustack` on its first boot. A deployment that never reads them out of the
volume can neither log in nor join a worker, so plan to fetch them once the pod is up.
