<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mysql-cluster

A highly-available **MySQL** cluster as an [Oracle MySQL Operator](https://github.com/mysql/mysql-operator)
`InnoDBCluster` custom resource — MySQL Group Replication fronted by MySQL Router.
This is the MySQL counterpart to [cnpg-cluster](../cnpg-cluster/): an app that needs
MySQL/MariaDB instead of PostgreSQL points its `dbHost` at this cluster's Service.

The Oracle operator is **Apache-2.0** (MySQL server itself is GPLv2 — fine to run;
GPL obligations attach to *distribution*, not operation).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';

kurly.list(mysql(name='orders-db', instances=3, storageSize='20Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mysql` | |
| `instances` | `3` | Group Replication members (odd count keeps a quorum) |
| `routerInstances` | `2` | MySQL Router instances — the routing tier apps connect through |
| `serverVersion` | `8.4.4` | the MySQL server version the operator pins |
| `storageSize` / `storageClass` | `10Gi` / cluster default | per-instance data volume |
| `secretName` | `mysql-root` | **you provide** this Secret — see below |
| `resources` / `tlsUseSelfSigned` / `imagePullSecrets` / `labels` / `annotations` | | |

Like `cnpg-cluster`, this authors a custom resource, so it is composed **by
parameter, not by `+` feature** — composing a kurly feature onto it fails the render
(it would silently do nothing). The raw `+` escape hatch still patches the CR.

## Prerequisites

1. Install the **MySQL Operator for Kubernetes** (`mysql-operator`) in the cluster.
2. Provide the **root-credentials Secret** (`secretName`). Unlike CloudNativePG,
   the Oracle operator does not mint it — it must exist with keys `rootUser`,
   `rootHost`, and `rootPassword`. kurly authors **no Secret**; fill it with
   [`kurly.externalSecret`](../../main.libsonnet):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-root
stringData:
  rootUser: root
  rootHost: "%"
  rootPassword: "<a strong password>"
```

## Connecting an app

Apps reach the cluster through the `<name>` Service (MySQL Router). Point a
MySQL-backed workload — [wordpress](../wordpress/), [invoiceninja](../invoiceninja/),
[mautic](../mautic/), … — at `dbHost: <name>` with the root (or an app) credential.
