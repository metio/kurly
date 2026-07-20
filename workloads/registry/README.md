<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# registry

[Docker Registry](https://distribution.github.io/distribution/) — the reference implementation of the OCI registry: a self-hosted store and distribution point for container images. A `kurly.http` workload on the official image; stored images on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local registry = import 'github.com/metio/kurly/workloads/registry/server.libsonnet';
kurly.list(registry())
```

Usually reached in-cluster (`registry:5000`); the [docker-registry-ui](../docker-registry-ui/) workload gives it a web interface. The bare registry is unauthenticated and plaintext — front it with TLS and auth, or keep it in-cluster. Images at `/var/lib/registry` on a ReadWriteOnce volume, so **one replica, recreated** (back it with S3 for a scaled registry). Serves on `:5000`.
