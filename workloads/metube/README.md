<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# metube

[MeTube](https://github.com/alexta69/metube) — a web UI for yt-dlp: paste a video or
playlist URL and it downloads it to a directory, with format and quality options. A plain
composable `kurly.http` workload on the official image; downloaded files live on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local metube = import 'github.com/metio/kurly/workloads/metube/server.libsonnet';
kurly.list(metube())
```

Downloads at `/downloads` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:8081`.
