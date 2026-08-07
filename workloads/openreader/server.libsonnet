// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openreader — an OpenReader server (a text-to-speech reader for EPUB, PDF,
// Markdown, plain text and DOCX documents: it reads a book aloud through a TTS
// provider and highlights the words as they are spoken). A plain composable
// kurly.http workload with no external dependency: the image carries its own
// SQLite database, an embedded SeaweedFS blob store and an embedded NATS
// JetStream, all of them under one directory on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local openreader = import 'github.com/metio/kurly/workloads/openreader/server.libsonnet';
//   kurly.list(openreader(baseUrl='https://read.example.com'))
//
// Serves the web app on :3003 — compose an exposure onto it. The Service also
// publishes :8333, the embedded SeaweedFS S3 endpoint, because uploads and
// downloads are PRESIGNED: the browser talks to that endpoint directly, so a
// deployment that exposes only the app accepts documents nowhere.
//
// BASE_URL is what the presigned URLs and the auth cookies are minted against,
// so the default here is a placeholder — pass the address users actually reach.
//
// Single writer: the database and the blob store share a ReadWriteOnce volume,
// so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='openreader',
  image=defaultImage,
  // The address users reach this instance at. Presigned upload URLs and the
  // session cookies are both derived from it.
  baseUrl='https://openreader.example.com',
  // Documents, the SQLite metadata database, the embedded blob store and the
  // JetStream state all live here.
  storageSize='20Gi',
  storageClass=null,
  // The TTS provider to seed on first boot. Read ONCE, at the first start —
  // afterwards it is administered from the web interface, so changing these
  // later moves nothing.
  apiBase=null,
  // The Secret holding AUTH_SECRET (32 random bytes, base64), which signs the
  // sessions, and optionally API_KEY for the TTS provider above.
  secretName='openreader',
  // Accounts that get administrator rights, as a comma-separated list.
  adminEmails=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3003)
  + kurly.servicePort(3003)
  // The embedded SeaweedFS S3 endpoint. Uploads and downloads are presigned and
  // fetched by the browser, not proxied through the app.
  + kurly.extraPort('s3', 8333)
  + kurly.env(
    {
      BASE_URL: baseUrl,
    }
    + (if apiBase != null then { API_BASE: apiBase } else {})
    + (if adminEmails != null then { ADMIN_EMAILS: adminEmails } else {})
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares no user, so pick the `node` account it ships (uid 1000)
  // rather than relaxing runAsNonRoot; fsGroup hands it the volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/docstore', storageSize, storageClass=storageClass)
  // Next.js keeps its incremental cache beside its own code, and the DOCX
  // conversion runs LibreOffice, which insists on a writable home.
  + kurly.scratch('/app/.next/cache')
  + kurly.scratch('/home/node')
  + kurly.scratch('/tmp')
  // First boot runs the migrations, unpacks the layout and alignment models and
  // starts the embedded blob store and broker before anything answers.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
