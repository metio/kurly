// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pdfding — a PdfDing server (a PDF manager, viewer and editor: upload documents,
// tag and search them, and pick up reading where you left off). A plain composable
// kurly.http workload: the uploaded PDFs and the SQLite database live together
// under DATA_DIR on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local pdfding = import 'github.com/metio/kurly/workloads/pdfding/server.libsonnet';
//   kurly.list(pdfding(hostName='pdf.example.com'))
//
// Serves the web app on :8000 — compose an exposure onto it.
//
// HOST_NAME IS DJANGO'S ALLOWED_HOSTS: a request whose Host header is not in that
// list is answered 400 before any view runs, so the placeholder default only works
// until the workload is really reachable somewhere. That is also why the probes
// check the LISTENING SOCKET rather than an HTTP path — a probe arriving with the
// pod IP as its Host would fail forever on a perfectly healthy pod.
//
// Single writer: one SQLite database and one media tree on a ReadWriteOnce volume,
// so one replica, recreated (never rolled). Point DATABASE_TYPE=POSTGRES and the
// POSTGRES_* variables at an external server through env to move the database off
// the volume; the uploaded PDFs stay on it either way.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pdfding',
  image=defaultImage,
  // The host names it answers on, comma separated. Django rejects every other Host.
  hostName='pdfding.example.com',
  // Uploaded PDFs and the SQLite database, both under DATA_DIR.
  dataDir='/data',
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding SECRET_KEY (and POSTGRES_PASSWORD when the database is
  // moved off the volume). SECRET_KEY signs sessions and password-reset links, so
  // a rotated or shared one logs everybody out or lets somebody else in.
  secretName='pdfding',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      HOST_NAME: hostName,
      DATA_DIR: dataDir,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image creates its own account at uid/gid 1000 and runs gunicorn as it; the
  // volume has to be group-owned by the same id or the first migration cannot write
  // the database file.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // gunicorn keeps its worker temporary files under /tmp, which is the only write
  // outside the volume.
  + kurly.scratch('/tmp')
  // huey keeps its task queue in a SQLite file under the application's HOME,
  // which is on the read-only root filesystem: it cannot create the file and
  // exits with "unable to open database file" before serving anything. HOME is
  // MOVED to the scratch rather than a volume being mounted over /home/nonroot —
  // that directory is also the working directory the entrypoint runs
  // ./bootstrap.sh from, and an empty volume on top of it hides the script, so
  // the container never starts at all. The queue is work-in-flight, not data
  // worth surviving the pod, so a scratch is the right home for it.
  + kurly.env({ HOME: '/tmp' })
  + kurly.store(dataDir, storageSize, storageClass=storageClass)
  // THE db/ SUBDIRECTORY OF THE VOLUME, which nothing else creates. Both SQLite
  // files live under DATA_DIR/db — Django's own and huey's tasks.sqlite3 — and
  // bootstrap.sh does not make the directory, so on a fresh volume sqlite3 cannot
  // create either file. What it reports is "unable to open database file", which
  // names no path at all and reads as a permission problem on a directory that is
  // in fact absent. Creating it is idempotent, so it runs before every start.
  + kurly.initContainer({
    name: 'create-data-dirs',
    image: image,
    command: ['/bin/sh', '-c', 'mkdir -p "$DATA_DIR/db"'],
    env: [{ name: 'DATA_DIR', value: dataDir }],
    volumeMounts: [{ name: 'store', mountPath: dataDir }],
  })
  // Migrations and the first-run setup happen before the socket is bound.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
