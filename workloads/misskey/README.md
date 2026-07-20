<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# misskey

[Misskey](https://misskey-hub.net) — a self-hosted, feature-rich ActivityPub/Fediverse social platform. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis, with uploaded files on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local misskey = import 'github.com/metio/kurly/workloads/misskey/server.libsonnet';
kurly.list(misskey())
```

Misskey reads its whole config (including DB/Redis credentials) from `/misskey/.config/default.yml`. Because that holds secrets, kurly mounts it from an **existing Secret** you provide (`misskey-config`, with a `default.yml` key) — kurly never mints key material. Files at `/misskey/files` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
