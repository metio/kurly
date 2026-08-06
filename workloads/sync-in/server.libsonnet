// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sync-in — a Sync-in server (file storage, syncing and sharing with real-time
// collaboration and per-space permissions). A composable kurly.http workload
// backed by an EXTERNAL MySQL/MariaDB — the mysql-cluster workload provides one —
// with the files themselves on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local syncin = import 'github.com/metio/kurly/workloads/sync-in/server.libsonnet';
//   kurly.list(syncin())
//
// Serves the web app and the sync API on :8080 — compose an exposure onto it.
//
// Configured entirely through SYNCIN_-prefixed environment variables: the server
// reads environment/environment.yaml and then overlays every SYNCIN_ variable whose
// dotted path exists in its shipped dist file, so no configuration document has to
// be authored. The credentials among them — the MySQL URL, the key that encrypts
// user secrets, and the two token signing secrets — come from a provided Secret via
// envFrom; kurly authors no Secret.
//
// Single writer: user and space files on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sync-in',
  image=defaultImage,
  // Personal spaces, shared spaces and the upload staging area.
  storageSize='20Gi',
  storageClass=null,
  // The Secret holding SYNCIN_MYSQL_URL, SYNCIN_AUTH_ENCRYPTIONKEY,
  // SYNCIN_AUTH_TOKEN_ACCESS_SECRET and SYNCIN_AUTH_TOKEN_REFRESH_SECRET. Every one
  // of them has a published placeholder in the project's own compose file, so
  // supplying them is the difference between having accounts and not. Optionally
  // INIT_ADMIN, INIT_ADMIN_LOGIN and INIT_ADMIN_PASSWORD, which the first start
  // uses to create the administrator account.
  secretName='sync-in',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      // The image's dist configuration points dataPath at /home/sync-in, which is
      // not where the image creates or mounts anything.
      SYNCIN_APPLICATIONS_FILES_DATAPATH: '/app/data',
      SYNCIN_SERVER_HOST: '0.0.0.0',
      SYNCIN_SERVER_PORT: '8080',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The entrypoint creates the account named by PUID/PGID, chowns the data volume
  // and drops to it with su-exec, which it can only do starting from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The first start migrates the schema and then marks it done by writing /app/.init
  // beside the application's own code.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // A Service named `syncin` would have Kubernetes inject SYNCIN_PORT and friends,
  // which is exactly the prefix the configuration loader treats as an override.
  + kurly.disableServiceLinks()
  // The first start waits for the database and runs the migrations before it
  // listens, and it probes by connection because every HTTP path either redirects
  // to the login page or answers 401.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
