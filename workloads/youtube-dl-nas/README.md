<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# youtube-dl-nas

[youtube-dl-nas](https://github.com/hyeonsangjeon/youtube-dl-nas) — a
password-protected web queue that hands URLs to `yt-dlp` and keeps the resulting
video, audio and subtitle files, with a download history. A plain composable
`kurly.http` workload keeping the downloads and its queue state on two
PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ytdlnas = import 'github.com/metio/kurly/workloads/youtube-dl-nas/server.libsonnet';

kurly.list(ytdlnas())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `youtube-dl-nas` | |
| `image` | `docker.io/modenaf360/youtube-dl-nas:latest` | |
| `downloadSize` | `50Gi` | `/downfolder` |
| `stateSize` | `1Gi` | `/usr/src/app/metadata` |
| `storageClass` | cluster default | both volumes |
| `secretName` | `youtube-dl-nas` | supplies `MY_ID` and `MY_PW` |
| `env` / `resources` / `labels` / `annotations` | | `env` merges over the defaults |

## The Secret

`MY_ID` and `MY_PW` are the single account that may reach the queue. There is no
other authentication and no way to run without one — the server refuses to start
when either is unset:

```shell
kubectl create secret generic youtube-dl-nas \
  --from-literal=MY_ID=admin \
  --from-literal=MY_PW="$(head -c 24 /dev/urandom | base64)"
```

## Why the hardened defaults are relaxed

The entrypoint runs as root on purpose: it substitutes the credentials into
`Auth.json` **inside its own install tree**, chowns the two volumes, and only then
drops to `PUID:PGID` with `gosu`. So this workload runs as root with a writable
root filesystem, privilege escalation allowed and capabilities kept. Set `PUID`
and `PGID` through `env` to have the downloaded files owned by an unprivileged
account.

## The auto-updaters are off

Both are disabled by default. yt-dlp's would `pip install` into the image's
site-packages on every start and write a log under `/var/log`; the subtitle-QA one
installs a further package. A container that reaches the internet to change itself
at boot is not what an allow-listed or air-gapped cluster deploys. Turn it back on
where keeping pace with YouTube's extractor changes matters more:

```jsonnet
ytdlnas(env={ YTDLP_AUTO_UPDATE: 'true' })
```

## It needs egress

Downloading is the whole point, so the pod reaches the public internet. Nothing
else about the manifest says so, and a NetworkPolicy written from its shape leaves
every job failing:

```jsonnet
ytdlnas() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443, 80] }])
```

## Persistence

One queue and one history file on ReadWriteOnce volumes, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: youtube-dl-nas }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-youtube-dl-nas, namespace: youtube-dl-nas }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/youtube-dl-nas, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: youtube-dl-nas }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-youtube-dl-nas, namespace: youtube-dl-nas }
spec: { sourceRef: { kind: OCIRepository, name: kurly-youtube-dl-nas } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: youtube-dl-nas, namespace: youtube-dl-nas }
spec:
  serviceAccountName: youtube-dl-nas-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/youtube-dl-nas/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-youtube-dl-nas, importPath: github.com/metio/kurly/workloads/youtube-dl-nas }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: youtube-dl-nas, namespace: youtube-dl-nas }
spec:
  serviceAccountName: youtube-dl-nas-deployer
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
        name: youtube-dl-nas
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: youtube-dl-nas }
```

<!-- END generated: jaas-deploy -->
