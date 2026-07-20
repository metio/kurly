<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# roundcube

[Roundcube](https://roundcube.net/) — a browser-based IMAP webmail client. A plain
composable `kurly.http` workload on the official image: it connects to an external
IMAP/SMTP mail server and keeps its own state (contacts, preferences) in a SQLite
database on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local roundcube = import 'github.com/metio/kurly/workloads/roundcube/server.libsonnet';

kurly.list(roundcube(
  imapHost='ssl://mail.example.com:993',
  smtpHost='tls://mail.example.com:587',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `roundcube` | |
| `image` | `docker.io/roundcube/roundcubemail:1.7.2-apache` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/var/roundcube/db`) |
| `imapHost` / `smtpHost` | required | the external IMAP / SMTP servers |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the webmail UI on `:80` — compose an exposure onto it. Point it at the
[mailu](../mailu/) workload (or any IMAP/SMTP server) via `imapHost`/`smtpHost`.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. The SQLite database lives on a ReadWriteOnce volume, so this
is **one replica, recreated**.
