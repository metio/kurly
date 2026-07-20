<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gokapi

[Gokapi](https://github.com/Forceu/Gokapi) — a self-hosted, lightweight file-sharing server with expiring links and a download limit, similar to the discontinued Firefox Send. A `kurly.http` workload on the official image; database, configuration and (by default) stored files on a PersistentVolume under `/app/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gokapi = import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet';
kurly.list(gokapi())
```

Data at `/app/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:53842`. Uploaded files can instead go to S3-compatible object storage when the `AWS_*` settings are provided.
