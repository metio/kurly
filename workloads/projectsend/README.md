<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# projectsend

[ProjectSend](https://www.projectsend.org) — a self-hosted, private file-sharing app: upload files and assign them to specific clients. A `kurly.http` workload on the LinuxServer.io image, backed by an external MySQL/MariaDB, with config and uploads on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local projectsend = import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='projectsend-db')).items,
  kurly.list(projectsend()).items,
]))
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config and uploads at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.
