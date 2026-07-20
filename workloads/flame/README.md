<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# flame

[Flame](https://github.com/pawelmalak/flame) — a self-hosted, minimalist start page and
application/bookmark dashboard for your homelab, with a built-in editor. A plain composable
`kurly.http` workload on the official image; its SQLite database lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local flame = import 'github.com/metio/kurly/workloads/flame/server.libsonnet';
kurly.list(flame())
```

Set the admin password through the `PASSWORD` environment variable (from a Secret via
`kurly.envFromSecret`); kurly authors **no Secret**. Data at `/app/data` on a ReadWriteOnce
volume, so **one replica, recreated**. Serves on `:5005`.
