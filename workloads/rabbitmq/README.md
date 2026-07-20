<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rabbitmq

[RabbitMQ](https://www.rabbitmq.com) — a widely-used, self-hosted message broker implementing AMQP. A `kurly.http` workload on the official management image; the broker speaks AMQP on `:5672`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rabbitmq = import 'github.com/metio/kurly/workloads/rabbitmq/server.libsonnet';
kurly.list(rabbitmq())
```

Single node. `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` come from a Secret via `envFrom` — kurly authors **no Secret**. The management UI (`:15672`) needs an extra Service. Data at `/var/lib/rabbitmq` on a ReadWriteOnce volume, so **one replica, recreated**. Serves AMQP on `:5672`.
