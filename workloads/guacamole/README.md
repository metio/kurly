<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# guacamole

[Apache Guacamole](https://guacamole.apache.org) — a clientless remote-desktop gateway: reach
RDP, VNC and SSH machines from a browser, no plugins. Guacamole is **two processes** — the web
app and the `guacd` proxy daemon — so this workload runs **guacd as a sidecar** in the same pod
(reached on `localhost:4822`), backed by an external PostgreSQL or MySQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local guacamole = import 'github.com/metio/kurly/workloads/guacamole/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='guacamole-db', database='guacamole')).items,
  kurly.list(guacamole()).items,
]))
```

The web app's database connection (`POSTGRESQL_*` / `MYSQL_*`) comes from a Secret via `envFrom`
— kurly authors **no Secret** — and the database schema must be initialised (see the Guacamole
docs). Stateless (connections and users live in the database). Serves on `:8080` (Guacamole is
under `/guacamole`).
