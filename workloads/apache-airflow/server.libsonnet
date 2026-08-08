// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// apache-airflow — an Apache Airflow instance (workflow orchestration: pipelines
// written as Python DAGs, scheduled, retried and observed). A plain composable
// kurly.http workload running the official image in `standalone` mode: one
// container holding the API server (the UI and REST API on :8080), the scheduler,
// the DAG processor and the triggerer, with the metadata database external.
//
//   local airflow = import 'github.com/metio/kurly/workloads/apache-airflow/server.libsonnet';
//   kurly.list(airflow(secretName='airflow'))
//
// Serves the UI and API on :8080 — compose an exposure onto it.
//
// DATABASE: Airflow keeps every DAG run, task instance and connection in a
// relational metadata database and cannot start without one. This pairs with the
// cnpg-cluster workload; the connection string comes from the Secret rather than
// a parameter, because it carries the password.
//
// SECRETS: secretName is read with envFrom, so its keys ARE Airflow settings.
// It must hold AIRFLOW__DATABASE__SQL_ALCHEMY_CONN (the SQLAlchemy URL of the
// metadata database), AIRFLOW__CORE__FERNET_KEY (encrypts stored connection and
// variable values — rotating it makes every existing one unreadable) and
// AIRFLOW__API_AUTH__JWT_SECRET (signs the tokens the UI and the task workers
// hold; unset, each restart invalidates every session and every running task's
// credentials). kurly authors no Secret; fill it with kurly.externalSecret.
//
// EXECUTOR: LocalExecutor by default — tasks run as subprocesses inside this pod,
// which is what makes a single-container Airflow coherent. Pointing the executor
// at Celery or Kubernetes needs the extra components those bring and is not what
// this stage renders.
//
// Single writer: one PersistentVolume holds AIRFLOW_HOME (the generated
// airflow.cfg, the DAG files, task logs), so this is one replica, recreated
// (never rolled) to keep two pods off the ReadWriteOnce volume. That volume is
// also how DAGs get in — mount or sync them into /opt/airflow/dags.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='apache-airflow',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The Secret read with envFrom: its keys are Airflow settings, and it carries
  // AIRFLOW__DATABASE__SQL_ALCHEMY_CONN, AIRFLOW__CORE__FERNET_KEY and
  // AIRFLOW__API_AUTH__JWT_SECRET. The consumer provides it; kurly mints none.
  secretName='apache-airflow',
  // Airflow ships a set of example DAGs. Off by default: they are tutorial
  // material, and every one of them shows up in a real deployment's UI.
  loadExamples=false,
  // Extra environment, merged over the below. Airflow reads its whole
  // configuration from AIRFLOW__<SECTION>__<KEY> variables, so this is where a
  // consumer's tuning goes. Anything sensitive belongs in the Secret.
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    AIRFLOW_HOME: '/opt/airflow',
    AIRFLOW__CORE__EXECUTOR: 'LocalExecutor',
    AIRFLOW__CORE__LOAD_EXAMPLES: (if loadExamples then 'True' else 'False'),
    AIRFLOW__API__HOST: '0.0.0.0',
    AIRFLOW__API__PORT: '8080',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image's entrypoint takes an airflow subcommand as its arguments;
  // `standalone` is the one that runs the API server, scheduler, DAG processor
  // and triggerer together, applying the database migrations first.
  + kurly.args(['standalone'])
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // The official image runs as uid 50000 in the root group, and its writable
  // directories are group-owned rather than user-owned; pin both plus the fsGroup
  // so AIRFLOW_HOME is writable and the restricted posture still admits the pod.
  + kurly.runAs(50000, gid=0, fsGroup=0)
  + kurly.store('/opt/airflow', storageSize, storageClass=storageClass)
  // Task subprocesses, the DAG processor and Python itself write scratch files
  // under /tmp; back it with an emptyDir so the root filesystem stays read-only.
  + kurly.scratch('/tmp', '1Gi')
  // First start applies the entire metadata-database migration set before
  // anything listens, so give it room rather than restarting it half way. Probe
  // by connection throughout: the API server answers 403 on the paths a probe
  // would otherwise reach, and a probe that reads one kills the pod forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 15, periodSeconds: 15, failureThreshold: 10 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 120, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
