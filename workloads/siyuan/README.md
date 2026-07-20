<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# siyuan

[SiYuan](https://github.com/siyuan-note/siyuan) — a privacy-first, self-hosted personal
knowledge-management and note-taking app with block-level editing and a local-first
workspace. A plain composable `kurly.http` workload on the official image; its workspace
(notes, assets and the database) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local siyuan = import 'github.com/metio/kurly/workloads/siyuan/server.libsonnet';
kurly.list(siyuan())
```

SiYuan's web access is gated by an access-auth code — set it through the
`SIYUAN_ACCESS_AUTH_CODE` environment variable (from a Secret via `kurly.envFromSecret`);
kurly authors no Secret. Workspace at `/siyuan/workspace` on a ReadWriteOnce volume, so
**one replica, recreated**. Serves on `:6806`.
