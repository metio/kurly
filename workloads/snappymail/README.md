<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# snappymail

[SnappyMail](https://snappymail.eu) — a fast, modern, self-hosted webmail client that connects to your existing IMAP/SMTP servers. A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); config and per-account data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local snappymail = import 'github.com/metio/kurly/workloads/snappymail/server.libsonnet';
kurly.list(snappymail())
```

SnappyMail is a client — configure your IMAP/SMTP servers in the admin panel. Data at `/var/lib/snappymail` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8888`.
