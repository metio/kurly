<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gitness

[Harness Open Source](https://github.com/harness/gitness) — the project Gitness was
renamed to. Git repositories, pull requests, an artifact registry and a web interface in
one binary, with SQLite underneath, so it needs no database beside it.

A plain composable `kurly.http` workload. The database, the repositories and the registry
blobs share one volume, which makes this a **single writer**: one replica, recreated
rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gitness = import 'github.com/metio/kurly/workloads/gitness/server.libsonnet';

kurly.list(
  gitness(url='https://git.example.com')
  + kurly.expose.gateway('git.example.com', parent='public')
)
```

## Pipelines and Gitspaces need a Docker daemon

The binary drives a Docker API to run pipeline steps and development environments, and
there is no daemon inside the pod. Repositories, pull requests, the registry and the web
interface all work; starting a pipeline reports that Docker is unreachable. `gitspaces`
defaults to off so the half that cannot work does not advertise itself.

## Two protocols, one Service

`:3000` is the web interface and API. `:3022` is git-over-SSH, published as the extra
port `ssh` — a raw TCP protocol that needs a TCP route, so an HTTP exposure publishes the
web interface and leaves SSH cloning unreachable.

## It phones home unless you say otherwise

The image ships with usage reporting enabled to an endpoint at the project. `metrics`
defaults to off here and writes the variable that keeps it off.
