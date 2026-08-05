// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// speedtest-tracker — a Speedtest Tracker server (runs internet speed tests on a
// schedule and keeps the history: download, upload and latency over time, with
// charts and alerting). A plain composable kurly.http workload: with the default
// SQLite backend its database lives on a PersistentVolume, so it needs nothing
// external. Import it and render with kurly.list:
//
//   local speedtestTracker = import 'github.com/metio/kurly/workloads/speedtest-tracker/server.libsonnet';
//   kurly.list(speedtestTracker(appUrl='https://speedtest.example.com'))
//
// Serves the web UI on :80 — compose an exposure onto it.
//
// WHAT IT MEASURES IS THE POD'S PATH TO THE INTERNET, not a home connection. Run
// from a cluster, the numbers describe the node's uplink and whatever egress sits
// in front of it, which is a useful thing to watch and not the thing most people
// install this for.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='speedtest-tracker',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The public URL the app builds links against.
  appUrl=null,
  // The Secret holding APP_KEY, which encrypts stored values. The entrypoint
  // generates one into its own .env when none is set, and that file is not on the
  // volume — so a restart would mint a new key and orphan what the old one wrote.
  secretName='speedtest-tracker',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    {
      DB_CONNECTION: 'sqlite',
      // Named explicitly: with DB_CONNECTION set to sqlite and no path, Laravel
      // refuses to start with "Ensure this is an absolute path to the database"
      // and the s6 supervisor tears the container down around it — so the error
      // that matters is several lines above the one that stops the pod.
      DB_DATABASE: '/config/database.sqlite',
    }
    + (if appUrl == null then {} else { APP_URL: appUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // An s6-overlay image: the init runs as root, prepares /config for the app
  // account and drops to it. There is no path through that as an unprivileged
  // process, so root, the capabilities the drop needs, and the escalation that
  // permits it are all genuinely required — the same shape as kurly's other
  // LinuxServer-style workloads.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // A Laravel application writing inside its own tree: the compiled configuration
  // cache and the .env the entrypoint writes are both beside the code, and neither
  // is data worth a volume.
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // Laravel opens the SQLite file, it does not create it — and neither does this
  // image, so a fresh volume produces a container that starts, migrates nothing,
  // and is torn down by its own supervisor with the real reason several lines above
  // the line that stops it. Creating the empty file is all that is needed; the
  // migrations then run against it. `test -f` keeps this to the first boot, so it
  // can never truncate a database that already holds history.
  + kurly.initContainer({
    name: 'create-database',
    image: image,
    command: ['sh', '-c', 'test -f /config/database.sqlite || install -m 0644 /dev/null /config/database.sqlite'],
    volumeMounts: [{ name: 'store', mountPath: '/config' }],
  })
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10, timeoutSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5 })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5, failureThreshold: 6 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
