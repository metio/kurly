<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# couchdb

[Apache CouchDB](https://couchdb.apache.org) — a self-hosted, document-oriented NoSQL database that speaks HTTP/JSON and syncs with offline-first apps. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local couchdb = import 'github.com/metio/kurly/workloads/couchdb/server.libsonnet';
kurly.list(couchdb())
```

`COUCHDB_USER` and `COUCHDB_PASSWORD` come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/opt/couchdb/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5984`.
