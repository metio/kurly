// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// harbor/jobservice — the Harbor worker: garbage collection, replication runs,
// retention, scans and webhook delivery. It takes its work from the same Redis
// core uses and reports back over the API, so it is an http stage (core calls it
// on :8080) rather than a worker.
//
//   local jobservice = import 'github.com/metio/kurly/workloads/harbor/jobservice.libsonnet';
//   kurly.list([jobservice(), …])
//
// Reads the same Secret as core — CORE_SECRET and JOBSERVICE_SECRET are how the
// two authenticate to each other, and REGISTRY_CREDENTIAL_PASSWORD is how it
// reaches the registry. kurly authors no Secret.
//
// Job logs are written to a PersistentVolume at /var/log/jobs, which is what the
// UI reads back when somebody opens a finished job: one volume, one writer, so
// this is one replica, recreated (never rolled) to keep two pods off the
// ReadWriteOnce volume. Setting `jobLogs='database'` puts the logs in PostgreSQL
// instead and claims no volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './jobservice.image', '\n');

function(
  name='harbor-jobservice',
  image=defaultImage,
  coreName='harbor-core',
  registryName='harbor-registry',
  redisHost='harbor-cache',
  redisPort='6379',
  registryUser='harbor_registry_user',
  secretName='harbor',
  // Where a job's log goes: 'file' (the PersistentVolume below) or 'database'.
  jobLogs='file',
  storageSize='1Gi',
  storageClass=null,
  // How many jobs run at once in this pod.
  maxJobWorkers=10,
  logLevel='info',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  assert jobLogs == 'file' || jobLogs == 'database' : 'harbor/jobservice: jobLogs must be "file" or "database", got ' + jobLogs;
  local coreUrl = 'http://%s:8080' % coreName;
  local level = std.asciiUpper(logLevel);
  // Written as data and manifested, not as a heredoc: the job logger stanza is a
  // nested list whose shape depends on jobLogs, and string interpolation into
  // indented YAML is how that goes wrong silently.
  local configYml = std.manifestYamlDoc({
    protocol: 'http',
    port: 8080,
    worker_pool: {
      workers: maxJobWorkers,
      backend: 'redis',
      redis_pool: {
        redis_url: 'redis://%s:%s/1' % [redisHost, redisPort],
        namespace: 'harbor_job_service_namespace',
        idle_timeout_second: 3600,
      },
    },
    job_loggers: [
      if jobLogs == 'file' then {
        name: 'FILE',
        level: level,
        settings: { base_dir: '/var/log/jobs' },
        sweeper: { duration: 14, settings: { work_dir: '/var/log/jobs' } },
      } else {
        name: 'DB',
        level: level,
        sweeper: { duration: 14 },
      },
    ],
    loggers: [{ name: 'STD_OUTPUT', level: level }],
    reaper: { max_update_hours: 24, max_dangling_hours: 168 },
  }) + '\n';
  local baseEnv = {
    CORE_URL: coreUrl,
    TOKEN_SERVICE_URL: coreUrl + '/service/token',
    REGISTRY_URL: 'http://%s:5000' % registryName,
    REGISTRY_CONTROLLER_URL: 'http://%s:8080' % registryName,
    REGISTRY_CREDENTIAL_USERNAME: registryUser,
    REGISTRY_HTTP_CLIENT_TIMEOUT: '90',
    JOBSERVICE_WEBHOOK_JOB_MAX_RETRY: '3',
    JOBSERVICE_WEBHOOK_JOB_HTTP_CLIENT_TIMEOUT: '3',
    LOG_LEVEL: logLevel,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  + kurly.runAs(10000, gid=10000, fsGroup=10000)
  + kurly.config({ 'config.yml': configYml }, mountPath='/etc/jobservice', subPath=true)
  + (if jobLogs == 'file' then
       kurly.store('/var/log/jobs', storageSize, storageClass=storageClass)
       + kurly.recreate()
     else kurly.scratch('/var/log/jobs', '256Mi'))
  + kurly.scratch('/tmp', '128Mi')
  // Every Harbor image starts by copying a CA bundle into /home/harbor, beside
  // its own binaries and entrypoint scripts, so the root filesystem has to be
  // writable: an emptyDir over that one path would shadow the install tree and
  // leave the container nothing to run.
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/stats', port: 'http' }, periodSeconds: 10 })
  + kurly.livenessProbe({ httpGet: { path: '/api/v1/stats', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 20 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
