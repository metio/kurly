<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# portainer

[Portainer CE](https://www.portainer.io) — a self-hosted management UI for Docker and Kubernetes. A `kurly.http` workload on the official image; its database and settings on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local portainer = import 'github.com/metio/kurly/workloads/portainer/server.libsonnet';
kurly.list(portainer(serviceAccountName='portainer'))
```

Database at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI on `:9000`.

To administer the cluster it runs in, Portainer needs a ServiceAccount bound to a ClusterRole (cluster-admin for full control). kurly authors no RBAC; create the ServiceAccount and binding yourself and pass its name as `serviceAccountName`.
