// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mirumoji — a Mirumoji server (a Japanese immersion toolkit: it tokenises the
// subtitles of a video, makes every word clickable for a dictionary lookup with a
// kanji breakdown, transcribes audio and exports flashcards). A plain composable
// kurly.http workload keeping its media, profiles and SQLite database on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local mirumoji = import 'github.com/metio/kurly/workloads/mirumoji/server.libsonnet';
//   kurly.list(mirumoji())
//
// Serves the FastAPI backend on :8000 — compose an exposure onto it.
//
// Upstream ships TWO images and this is the BACKEND one: the React frontend the
// project's compose file also starts is not carried here, because it terminates
// TLS itself with a certificate authority it mints at runtime — a job an Ingress
// or an HTTPRoute already does. Point a browser client at this API instead.
//
// Everything the dictionary needs is baked into the image (the UniDic dictionary
// in site-packages, the Kotobase databases under /root/.cache — half a gigabyte
// of them), so nothing is downloaded at start and the workload works with no
// egress at all. Egress is only needed for the OPTIONAL features: an LLM provider
// for sentence breakdowns, and Modal for offloaded transcription.
//
// It runs as ROOT, which is unusual here and deliberate: the server resolves its
// storage through platformdirs under $HOME, and the baked dictionary cache sits
// in root's home at mode 0700 — an unprivileged account cannot even traverse into
// it, so the lookups a fresh install is supposed to answer would all fail. The
// root filesystem stays read-only (Kotobase opens its databases read-only) and no
// capability or escalation is granted.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mirumoji',
  image=defaultImage,
  // Uploaded media, generated clips, profiles and the SQLite database.
  storageSize='20Gi',
  storageClass=null,
  // 'auto' picks local faster-whisper where a GPU is visible and Modal where its
  // tokens are set; 'modal' and 'local' pin one of the two.
  transcribeBackend='auto',
  logLevel='INFO',
  // The Secret holding the OPTIONAL keys for the features that leave the cluster:
  // OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, MIRUMOJI_LLM_API_KEY and
  // MIRUMOJI_LLM_BASE_URL for sentence breakdowns and subtitle refinement, and
  // MODAL_TOKEN_ID / MODAL_TOKEN_SECRET for offloaded transcription. Without it
  // the subtitles, the dictionary and the flashcards all still work.
  secretName=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // uvicorn binds :8000 in the image's own command.
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      MIRUMOJI_TRANSCRIBE_BACKEND: transcribeBackend,
      MIRUMOJI_LOGGING_LEVEL: logLevel,
    } + env
  )
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // Every setting the server reads is named MIRUMOJI_*, and a Service named after
  // this workload makes Kubernetes inject MIRUMOJI_PORT as a tcp:// URL into that
  // same namespace of names.
  + kurly.disableServiceLinks()
  // The image selects no account, and the dictionary databases it bakes in live
  // in root's home directory at mode 0700.
  + kurly.rootUser()
  + kurly.store('/root/.local/share/mirumoji', storageSize, storageClass=storageClass)
  // Logs go to the platformdirs state directory; ffmpeg writes its intermediate
  // audio and clip files to the temporary directory.
  + kurly.scratch('/root/.local/state/mirumoji')
  + kurly.scratch('/tmp')
  // Importing the tokeniser and opening the dictionary databases takes a while on
  // the first start, and the image is large enough that the pull dominates it.
  + kurly.startupProbe({ httpGet: { path: '/health/status', port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/health/status', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health/status', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
