<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongodb-cluster

A highly-available **MongoDB** replica set as a
[MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator)
`MongoDBCommunity` custom resource. This is the document-database counterpart to
[cnpg-cluster](../cnpg-cluster/).

## ⚠ Licensing — read this first

MongoDB **Community Edition is licensed under the SSPL**, which restricts *offering
MongoDB as a service* — the same clause that makes Elasticsearch unsuitable for a
monetized hosting platform. The **operator** is Apache-2.0, but the **server** is
not. If SSPL is a problem for your business model, prefer **[FerretDB](https://www.ferretdb.com/)**
(Apache-2.0, MongoDB-wire-compatible, runs on PostgreSQL) instead.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongodb = import 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet';

kurly.list(mongodb(name='sessions', members=3, storageSize='20Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mongodb` | |
| `members` | `3` | replica-set members (odd count keeps a quorum) |
| `mongodbVersion` | `8.0.4` | the MongoDB server version |
| `storageSize` / `storageClass` | `10Gi` / cluster default | per-member data volume |
| `logsSize` | `2Gi` | per-member logs volume |
| `adminUser` | `admin` | created on bootstrap |
| `secretName` | `mongodb-admin` | **you provide** this Secret (key `password`) |
| `labels` / `annotations` | | |

Like `cnpg-cluster`, this authors a custom resource, so it is composed **by
parameter, not by `+` feature**.

## Prerequisites

1. Install the **MongoDB Community Operator** (`mongodb-kubernetes-operator`).
2. Provide the admin-password **Secret** (`secretName`) with a `password` key. kurly
   authors **no Secret**; fill it with [`kurly.externalSecret`](../../main.libsonnet).
