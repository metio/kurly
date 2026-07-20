<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mattermost

[Mattermost](https://mattermost.com) — a self-hosted, open-source team messaging
platform: channels, threads, and integrations, à la Slack. A plain composable
`kurly.http` workload on the Team Edition image, backed by an external PostgreSQL, with
its file uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mattermost = import 'github.com/metio/kurly/workloads/mattermost/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='mattermost-db', database='mattermost')).items,
  kurly.list(mattermost(siteUrl='https://chat.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mattermost` | |
| `image` | `docker.io/mattermost/mattermost-team-edition:11.8.4` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | uploads (`/mattermost/data`) |
| `siteUrl` | inferred | the public URL |
| `secretName` | `mattermost-secrets` | Secret with `MM_SQLSETTINGS_DATASOURCE` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:8065` — compose an exposure onto it.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.
Point the file store at S3 (`MM_FILESETTINGS_DRIVERNAME=amazons3`) to run more than one
replica.
