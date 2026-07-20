<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# convertx

[ConvertX](https://github.com/C4illin/ConvertX) — a self-hosted online file converter supporting 1000+ formats. A `kurly.http` workload on the official image; SQLite database and in-flight files on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local convertx = import 'github.com/metio/kurly/workloads/convertx/server.libsonnet';
kurly.list(convertx())
```

Set `JWT_SECRET` from a Secret via `envFrom`; kurly authors **no Secret**. Data at `/app/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.
