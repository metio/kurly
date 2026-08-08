// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// druid-middle-manager — the Apache Druid MiddleManager: it takes ingestion tasks
// from the Overlord and runs each one in a forked peon process, which reads the
// input, builds segments and publishes them to deep storage. Without this stage a
// Druid deployment can query what it already holds and ingest nothing. Deploy it
// after the coordinator.
//
//   local middleManager = import 'github.com/metio/kurly/workloads/druid/middle-manager.libsonnet';
//   kurly.list(middleManager())
//
// Serves the worker API on :8091, and each running task on a port from 8100 up.
// Neither is something to expose.
//
// The PEONS RUN INSIDE THIS POD, each its own JVM: workerCapacity multiplied by
// the peon heap is memory this container needs on top of its own, which is why
// its limit is well above its heap. Scale ingestion with kurly.replicas, or with
// workerCapacity where a single pod has the memory for it.
//
// NO ZOOKEEPER. Every stage runs Druid's Kubernetes discovery extension
// (druid.discovery.type=k8s) with HTTP-based segment and task management, so the
// services find one another and elect leaders through the Kubernetes API instead
// of a ZooKeeper ensemble — which is why each stage asks for a Role over pods and
// configmaps in its own namespace. All stages of one Druid cluster must share a
// namespace and a clusterIdentifier.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './middle-manager.image', '\n');

function(
  name='druid-middle-manager',
  image=defaultImage,
  // The Druid cluster every stage announces itself into. It must match across the
  // stages, must be unique per Druid cluster in the Kubernetes cluster, and the
  // extension requires it to match [a-z0-9][a-z0-9-]*[a-z0-9].
  clusterIdentifier='druid',
  // The PostgreSQL holding Druid's metadata (datasources, segments, task and
  // supervisor state). Not optional and not swappable at runtime: every stage
  // must point at the same one.
  dbHost='druid-db-rw',
  dbPort=5432,
  dbName='druid',
  dbUser='druid',
  // Deep storage — where segments and task logs actually live. An S3-compatible
  // bucket, because deep storage is read and written by several stages at once
  // and a ReadWriteOnce volume cannot be.
  bucket='druid',
  // Absent for AWS S3 itself; set it to the endpoint of a MinIO, SeaweedFS or
  // Ceph gateway. Path-style addressing is on, which is what those gateways serve.
  s3Endpoint=null,
  s3Region='us-east-1',
  // The Secret holding druid_metadata_storage_connector_password, druid_s3_accessKey
  // and druid_s3_secretKey. kurly authors none. The keys are env var names the
  // image translates into Druid properties (`_` becomes `.`), which is how a
  // credential reaches Druid without a configuration file.
  secretName='druid',
  // Heap and off-heap budgets, as the image's DRUID_* knobs read them. The
  // configuration baked into the image is sized for a dedicated machine (multi-GiB
  // buffers), so a stage that did not override these would not fit any modest
  // container.
  heap='256m',
  directMemory='128m',
  // How many ingestion tasks this worker runs at once, and what each forked peon
  // gets. The image's defaults are 4 tasks at 1g of heap and 1g of direct memory
  // each, which no modest container can hold.
  workerCapacity=2,
  peonHeap='512m',
  peonDirectMemory='256m',
  // Working directories: the task tree each peon unpacks its input into, and the
  // task logs before they are shipped to deep storage. Ephemeral by design — a
  // task that dies with its pod is retried by the Overlord.
  varSize='10Gi',
  replicas=1,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  // The pod must know its own name and namespace for the discovery extension to
  // announce it, and druid.host is what the other services dial — a pod's own
  // hostname does not resolve, so it advertises its routable IP. A manifest patch
  // rather than a config knob: kurly has no downward-API env feature, and adding
  // to the container survives later composition.
  local downwardEnv = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container {
          env+: [
            { name: 'POD_NAME', valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } },
            { name: 'POD_NAMESPACE', valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' } } },
            { name: 'druid_host', valueFrom: { fieldRef: { fieldPath: 'status.podIP' } } },
          ],
        }
        for container in super.containers
      ],
    } } } },
  };

  local baseEnv = {
    druid_extensions_loadList: '["druid-kubernetes-extensions", "postgresql-metadata-storage", "druid-s3-extensions", "druid-datasketches", "druid-kafka-indexing-service"]',
    druid_zk_service_enabled: 'false',
    druid_serverview_type: 'http',
    druid_indexer_runner_type: 'httpRemote',
    druid_discovery_type: 'k8s',
    druid_discovery_k8s_clusterIdentifier: clusterIdentifier,
    druid_metadata_storage_type: 'postgresql',
    druid_metadata_storage_connector_connectURI: 'jdbc:postgresql://%s:%d/%s' % [dbHost, dbPort, dbName],
    druid_metadata_storage_connector_user: dbUser,
    druid_storage_type: 's3',
    druid_storage_bucket: bucket,
    druid_storage_baseKey: 'druid/segments',
    druid_indexer_logs_type: 's3',
    druid_indexer_logs_s3Bucket: bucket,
    druid_indexer_logs_s3Prefix: 'druid/indexing-logs',
    druid_s3_enablePathStyleAccess: 'true',
    druid_s3_endpoint_signingRegion: s3Region,
    [if s3Endpoint != null then 'druid_s3_endpoint_url']: s3Endpoint,
    druid_emitter: 'noop',
    // The image's cluster configuration dumps every resolved property, including a
    // classpath of several hundred jars, before it logs anything useful.
    druid_startup_logging_logProperties: 'false',
    druid_worker_capacity: std.toString(workerCapacity),
    druid_server_http_numThreads: '20',
    druid_indexer_runner_javaOptsArray: '["-server", "-Xms%s", "-Xmx%s", "-XX:MaxDirectMemorySize=%s", "-Duser.timezone=UTC", "-Dfile.encoding=UTF-8", "-XX:+ExitOnOutOfMemoryError", "-Djava.util.logging.manager=org.apache.logging.log4j.jul.LogManager"]' % [peonHeap, peonHeap, peonDirectMemory],
    druid_indexer_fork_property_druid_processing_numMergeBuffers: '2',
    druid_indexer_fork_property_druid_processing_buffer_sizeBytes: '25MiB',
    druid_indexer_fork_property_druid_processing_numThreads: '1',
    // The image's own log4j2 configuration writes to ROLLING FILES under
    // /opt/druid/log and routes NOTHING to stdout, so on a read-only root
    // filesystem the appender cannot be created, every other appender fails with
    // it, and the process exits with its own error message logged nowhere anybody
    // can read it. Replacing the configuration with a console-only one is what
    // makes `kubectl logs` work at all here.
    DRUID_LOG4J: '<?xml version="1.0" encoding="UTF-8" ?><Configuration status="WARN"><Appenders><Console name="Console" target="SYSTEM_OUT"><PatternLayout pattern="%d{ISO8601} %p [%t] %c - %m%n"/></Console></Appenders><Loggers><Root level="info"><AppenderRef ref="Console"/></Root></Loggers></Configuration>',
    DRUID_XMS: heap,
    DRUID_XMX: heap,
    DRUID_MAXDIRECTMEMORYSIZE: directMemory,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8091)
  + kurly.servicePort(8091)
  // The first argument to the image's entrypoint is the service to run; the
  // configuration it picks up comes from the image's own cluster config tree.
  + kurly.args(['middleManager'])
  + kurly.env(baseEnv + env)
  // The discovery extension announces a pod by PATCHING its own annotations, and
  // a JSON patch cannot add a key under a path that does not exist: a pod with no
  // annotations at all is rejected with a 422 the moment it tries, and the service
  // exits rather than start unannounced. This annotation is the path.
  + kurly.podAnnotations({ 'kurly.metio.wtf/druid-service': 'middleManager' })
  + kurly.envFromSecret(secretName)
  + downwardEnv
  // Discovery and leader election are Kubernetes API operations: each pod labels
  // itself, watches its peers, and takes a lease through a ConfigMap. Declared as
  // an API-server client so the Role, the ServiceAccount and the egress travel
  // with the workload and merge with a consumer's own rbac()/networkPolicy().
  + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods', 'configmaps'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'] }])
  // The image ships a `druid` account (uid 1000) and the entrypoint does no
  // chown, so the restricted posture holds untouched.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The entrypoint copies the whole config tree to /tmp/conf and rewrites it from
  // the environment — the image is written for a read-only root filesystem and
  // this is the directory that makes it work.
  + kurly.scratch('/tmp', '256Mi')
  // WORKDIR is /opt/druid and the entrypoint creates var/tmp, var/druid/* under
  // it before the JVM starts.
  + kurly.scratch('/opt/druid/var', varSize)
  // A cold JVM takes far longer than a liveness probe's patience, and /status
  // answers nothing until it is done — so the wait is a startup probe rather than
  // a stretched liveness delay.
  + kurly.startupProbe({ httpGet: { path: '/status/health', port: 'http' }, failureThreshold: 60, periodSeconds: 5 })
  // /status/ready is the endpoint the discovery extension itself keys on: a pod
  // is discoverable only while its container is Ready.
  + kurly.readinessProbe({ httpGet: { path: '/status/ready', port: 'http' }, periodSeconds: 10, failureThreshold: 3, timeoutSeconds: 10 })
  + kurly.livenessProbe({ httpGet: { path: '/status/health', port: 'http' }, periodSeconds: 20, failureThreshold: 5 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
