<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# penpot

[Penpot](https://penpot.app) — the self-hosted, open-source design and prototyping platform, an
alternative to Figma. It runs as **three workloads** — a `backend` (API + data), a `frontend`
(the nginx-served web app that proxies to the others), and an `exporter` (headless-browser
rendering) — backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/penpot/backend.libsonnet';
local frontend = import 'github.com/metio/kurly/workloads/penpot/frontend.libsonnet';
local exporter = import 'github.com/metio/kurly/workloads/penpot/exporter.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='penpot-db', database='penpot')).items,
  kurly.list(backend()).items,
  kurly.list(frontend()).items,
  kurly.list(exporter()).items,
]))
```

All three stages share a Secret (`penpot-secrets`) via `envFrom` holding the PostgreSQL/Redis
connection and `PENPOT_SECRET_KEY` — kurly authors **no Secret**. The **frontend** is the
user-facing stage on `:80` and reaches the backend/exporter by their Service names; the backend
serves the API on `:6060` with uploaded assets on a ReadWriteOnce volume (one replica, recreated —
or put assets on S3 to scale out); the exporter serves on `:6061`.
