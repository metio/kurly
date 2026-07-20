<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# filebrowser

[File Browser](https://github.com/filebrowser/filebrowser) — a self-hosted web file
manager: browse, upload, edit and share files from a directory through a clean UI. A
plain composable `kurly.http` workload on the official image; its SQLite database lives
on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local filebrowser = import 'github.com/metio/kurly/workloads/filebrowser/server.libsonnet';
kurly.list(filebrowser())
```

File Browser manages the directory mounted at `/srv` — compose the volume you want to
serve onto that path. The config volume holds only the app's own database (`/database`),
on a ReadWriteOnce volume, so this is **one replica, recreated**. Serves on `:80`.
