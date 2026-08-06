<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homegallery

[HomeGallery](https://home-gallery.org) — a self-hosted photo and video gallery that indexes the
folders your media already lives in and offers a timeline, similarity search and face detection.
A `kurly.http` workload on the official image: configuration, database and preview storage all
live under `/data` on one PersistentVolume, so it needs **no external database**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homegallery = import 'github.com/metio/kurly/workloads/homegallery/server.libsonnet';

kurly.list(homegallery())
```

The image sets `HOME`, `GALLERY_BASE_DIR` and `GALLERY_CACHE_DIR` to `/data` and
`GALLERY_CONFIG_DIR` to `/data/config`, so the configuration written on first start, the database
file and the generated previews land on the single volume — and so does the media, under
`/data/Pictures` by default. Size `storageSize` for the library, not for the database.

The entrypoint is the CLI (`node /app/gallery.js`) and the image carries no default command, so
the stage passes `run server` as the container args — the subcommand that starts the web server
and imports and watches the source directories. `run server` **refuses to start without a
configuration file** and writes none itself, so an empty volume would crash-loop the pod: an init
container runs `run init --source …` once, naming the `sources` to index (`/data/Pictures` by
default), and is skipped when the file is already there. Similarity search and face detection are computed
by a separate embedding API; `apiServer` points at one, and setting it to your own
`xemle/home-gallery-api-server` keeps the media inside the cluster.

The server binds `:3000` as the image's own `node` user, so it runs as `1000:1000` with a
read-only root filesystem, with only `/tmp` writable for ffmpeg's and vips' temporary files. The
first start writes a configuration and imports the whole library before the web app answers, so a
generous startup probe carries that wait. The volume is ReadWriteOnce, so this is **one replica,
recreated**. Serves on `:3000` — compose an exposure onto it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

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
metadata: { name: kurly, namespace: homegallery }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-homegallery, namespace: homegallery }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/homegallery, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: homegallery }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-homegallery, namespace: homegallery }
spec: { sourceRef: { kind: OCIRepository, name: kurly-homegallery } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: homegallery, namespace: homegallery }
spec:
  serviceAccountName: homegallery-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/homegallery/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-homegallery, importPath: github.com/metio/kurly/workloads/homegallery }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: homegallery, namespace: homegallery }
spec:
  serviceAccountName: homegallery-deployer
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
        name: homegallery
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: homegallery }
```

<!-- END generated: jaas-deploy -->
