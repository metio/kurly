<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# alist

[AList](https://alist.nn.ci) — a self-hosted file list / WebDAV program fronting many storage backends (local disk, S3, WebDAV, cloud drives) behind one web UI. A `kurly.http` workload on the official image; SQLite database and configuration on a PersistentVolume under `/opt/alist/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local alist = import 'github.com/metio/kurly/workloads/alist/server.libsonnet';
kurly.list(alist())
```

Data at `/opt/alist/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI and WebDAV on `:5244`. On first start it logs a randomly generated admin password — read it from the pod logs.
