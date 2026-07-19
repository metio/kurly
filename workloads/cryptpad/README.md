<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cryptpad

[CryptPad](https://cryptpad.org/) — end-to-end encrypted, collaborative documents,
spreadsheets, and more. A plain composable `kurly.http` workload on the official
image that keeps its encrypted blocks, blobs, and datastore on a PersistentVolume,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cryptpad = import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet';

kurly.list(cryptpad())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cryptpad` | |
| `image` | `docker.io/cryptpad/cryptpad:2026.5.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the encrypted datastore (`/cryptpad/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the app on `:3000` — compose an exposure onto it.

## Configuration

CryptPad needs a `config.js` at `/cryptpad/config/config.js` setting
`httpUnsafeOrigin` (the main URL) and `httpSafeOrigin` (a **separate sandbox
domain** — required for its security model). Mount it with `kurly.config`; both
origins must resolve to this Service.

## Security and persistence

The Node app writes to several paths under `/cryptpad` at runtime, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. The encrypted datastore lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.
