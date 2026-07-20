<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# filestash

[Filestash](https://www.filestash.app) — a self-hosted web file manager with a modern UI in front of many storage backends (SFTP, FTP, S3, WebDAV, Git). A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local filestash = import 'github.com/metio/kurly/workloads/filestash/server.libsonnet';
kurly.list(filestash())
```

Add storage backends in the admin console; files live on those backends. Config at `/app/data/state` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8334`.
