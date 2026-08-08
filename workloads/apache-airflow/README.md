<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apache-airflow

[Apache Airflow](https://airflow.apache.org/) — workflow orchestration: pipelines
written as Python DAGs, then scheduled, retried and observed. One composable
stage, `server`, running the
[official image](https://github.com/apache/airflow) in `standalone` mode: a single
container holding the API server (the UI and REST API), the scheduler, the DAG
processor and the triggerer.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local airflow = import 'github.com/metio/kurly/workloads/apache-airflow/server.libsonnet';

kurly.list(
  airflow(secretName='airflow')
  + kurly.expose.gateway('airflow.example.com', 'public', 'gateways')
)
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `apache-airflow` | |
| `image` | `docker.io/apache/airflow:3.3.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `AIRFLOW_HOME` — config, DAG files, task logs |
| `secretName` | `apache-airflow` | read with `envFrom` — see below |
| `loadExamples` | `false` | Airflow's tutorial DAGs |
| `env` | `{}` | extra `AIRFLOW__<SECTION>__<KEY>` settings, merged over the defaults |
| `resources` / `labels` / `annotations` | | |

Serves the UI and API on `:8080`. Exposure is a separate axis — compose
`kurly.expose.*` onto it.

## Database

Airflow keeps every DAG run, task instance, connection and variable in a
relational metadata database and will not start without one. This pairs with the
`cnpg-cluster` workload. The connection string is not a parameter: it carries the
password, so it lives in the Secret with the rest of the credentials.

## Secrets

`secretName` is read with `envFrom`, which means its keys *are* Airflow settings.
kurly authors no Secret — fill it with `kurly.externalSecret` or your own.

| Key | What it does |
|---|---|
| `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` | the SQLAlchemy URL of the metadata database |
| `AIRFLOW__CORE__FERNET_KEY` | encrypts stored connections and variables — rotate it and every existing one becomes unreadable |
| `AIRFLOW__API_AUTH__JWT_SECRET` | signs the tokens the UI and running tasks hold — unset, every restart invalidates them |

## Executor, and what one container can do

`LocalExecutor` by default: tasks run as subprocesses inside this pod, which is
what makes a single-container Airflow coherent. The Celery and Kubernetes
executors bring their own components (a broker and result backend, or per-task
pods and the RBAC to create them) and this stage renders none of them.

## DAGs and scaling

`AIRFLOW_HOME` is one ReadWriteOnce volume, and `/opt/airflow/dags` on it is how
pipelines get in — sync them there, or mount your own volume over that path. One
volume also means one writer: this is one replica, recreated rather than rolled,
so two pods never contend for it.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: apache-airflow }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-apache-airflow, namespace: apache-airflow }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/apache-airflow, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: apache-airflow }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-apache-airflow, namespace: apache-airflow }
spec: { sourceRef: { kind: OCIRepository, name: kurly-apache-airflow } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: apache-airflow, namespace: apache-airflow }
spec:
  serviceAccountName: apache-airflow-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/apache-airflow/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-apache-airflow, importPath: github.com/metio/kurly/workloads/apache-airflow }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: apache-airflow, namespace: apache-airflow }
spec:
  serviceAccountName: apache-airflow-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: apache-airflow
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: apache-airflow }
```

<!-- END generated: jaas-deploy -->
