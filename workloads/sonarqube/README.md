<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sonarqube

[SonarQube](https://www.sonarsource.com/products/sonarqube/) — continuous
code-quality and static-analysis inspection. A plain composable `kurly.http`
workload on the official Community image, backed by an external PostgreSQL, with
its data, extensions, and embedded search index on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sonarqube = import 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='sonarqube-db', database='sonarqube')).items,
  kurly.list(sonarqube()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sonarqube` | |
| `image` | `docker.io/library/sonarqube:26.7.0.124771-community` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | data, extensions, search index |
| `dbHost` / `dbName` / `dbUser` | `sonarqube-db-rw` / `sonarqube` / `sonarqube` | the PostgreSQL database |
| `secretName` | `sonarqube-secrets` | Secret with `SONAR_JDBC_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:9000` — compose an exposure onto it.

## Host requirement: `vm.max_map_count`

SonarQube's embedded Elasticsearch needs the node's `vm.max_map_count` to be at
least **262144**. Set it on the node (a bootstrap DaemonSet, node config, or the
kubelet). kurly deliberately does **not** inject a privileged initContainer to
change it — that would break the hardened posture and admission under
[bollwerk](../../bollwerk/).

## Database and secrets

SonarQube reads `SONAR_JDBC_URL` and `SONAR_JDBC_USERNAME` from env and
`SONAR_JDBC_PASSWORD` from a provided Secret via `envFrom`. The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `sonarqube-db`. kurly authors **no Secret** —
fill `sonarqube-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Persistence

The search index and data live on a ReadWriteOnce volume, so this is **one replica,
recreated**.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: sonarqube }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sonarqube, namespace: sonarqube }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sonarqube, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sonarqube }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sonarqube, namespace: sonarqube }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sonarqube } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sonarqube, namespace: sonarqube }
spec:
  serviceAccountName: sonarqube-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sonarqube, importPath: github.com/metio/kurly/workloads/sonarqube }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sonarqube, namespace: sonarqube }
spec:
  serviceAccountName: sonarqube-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: sonarqube
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sonarqube }
```

<!-- END generated: jaas-deploy -->
