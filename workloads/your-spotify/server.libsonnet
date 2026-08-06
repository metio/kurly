// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// your-spotify — a Your Spotify server (a self-hosted dashboard of your own Spotify
// listening history and statistics). A plain composable kurly.http workload on the
// official server image, backed by an external MongoDB. Import it, point it at
// MongoDB, and render with kurly.list:
//
//   local yourSpotify = import 'github.com/metio/kurly/workloads/your-spotify/server.libsonnet';
//   kurly.list(yourSpotify(apiEndpoint='https://spotify-api.example.com',
//                          clientEndpoint='https://spotify.example.com'))
//
// Serves the API on :8080 — compose an exposure onto it. The web client is a separate
// image not carried here; apiEndpoint/clientEndpoint are the public URLs the server
// builds its Spotify OAuth redirect from, so both must be reachable by the browser.
//
// DATABASE & SECRETS: the server reads MONGO_ENDPOINT plus the Spotify application
// credentials (SPOTIFY_PUBLIC, SPOTIFY_SECRET) from the environment. kurly authors no
// Secret; provide one holding them, pulled in via envFrom. MONGO_ENDPOINT is the
// whole connection string, so the MongoDB is entirely the consumer's to provide.
//
// Stateless: every scrobble lands in MongoDB, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='your-spotify',
  image=defaultImage,
  replicas=2,
  // The public URL of THIS server — the Spotify OAuth redirect is built from it.
  apiEndpoint=null,
  // The public URL of the web client that talks to this server.
  clientEndpoint=null,
  // The Secret holding MONGO_ENDPOINT, SPOTIFY_PUBLIC and SPOTIFY_SECRET (kurly
  // mints none), via envFrom.
  secretName='your-spotify',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { PORT: '8080' }
    + (if apiEndpoint == null then {} else { API_ENDPOINT: apiEndpoint })
    + (if clientEndpoint == null then {} else { CLIENT_ENDPOINT: clientEndpoint });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  // The API validates nothing on / and answers plainly, but it reaches MongoDB
  // before it serves, so probe by connection and let a database outage show up as
  // an unready pod rather than a restart loop.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
