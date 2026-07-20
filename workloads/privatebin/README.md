<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# privatebin

[PrivateBin](https://privatebin.info) — a minimalist, open-source, zero-knowledge
pastebin: the server stores only encrypted blobs, with pastes encrypted and decrypted in
the browser. A plain composable `kurly.http` workload on the official nginx+php-fpm image;
with the default filesystem backend its encrypted pastes live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local privatebin = import 'github.com/metio/kurly/workloads/privatebin/server.libsonnet';
kurly.list(privatebin())
```

Pastes at `/srv/data` on a ReadWriteOnce volume, so **one replica, recreated**. Point
PrivateBin at an external database (its `conf.php`) to scale out. Serves on `:8080`.
