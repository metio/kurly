---
name: kurly
description: >-
  Compose Kubernetes workloads with kurly — a Jsonnet library of composable
  workload recipes on top of k8s-libsonnet. Use this when authoring or editing a
  workload in Jsonnet: start from a base kind (kurly.http / kurly.worker /
  kurly.cron / kurly.daemon), add capabilities as composable + features
  (kurly.store, kurly.config, kurly.expose.*, kurly.security.*, kurly.runAs,
  kurly.recreate, …), render with kurly.list, or start from a published workload
  under workloads/<name>/ and adapt it. Applies whenever a repo imports
  github.com/metio/kurly, when wiring a kurly workload into JaaS
  (JsonnetSnippet / JsonnetLibrary) and stageset-controller (StageSet), or when a
  kurly.* composition needs to render.
allowed-tools: Bash(jsonnet *), Bash(jb *), Bash(kubectl *)
---

# Composing workloads with kurly

**kurly** (`github.com/metio/kurly`) is a Jsonnet library of Kubernetes workload
recipes built on [k8s-libsonnet](https://github.com/jsonnet-libs/k8s-libsonnet).
You start from a **base kind** and add capabilities as composable **`+`
features**:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';

kurly.list(
  kurly.http('storefront', 'ghcr.io/acme/storefront:1.2.3')  // the base
  + kurly.store('/var/lib/store', '5Gi')                     // features, any order
  + kurly.recreate()
  + kurly.security.baseline                                  // security is a feature too
  + kurly.expose.gateway('storefront.example.com', 'shared') // so is exposure
)
```

A base kind returns an object whose hidden `config::` holds every knob and whose
visible fields are the manifests, computed from that config. A feature is a
`{ config+:: … }` mixin — it only ever writes `config`, never a manifest — so the
manifests **late-bind against the merged config regardless of compose order**.
`kurly.list(app)` wraps every manifest (including hidden owned ones like the
store PVC and config ConfigMap) in a `kind: List`. To assemble several parts
into one list, use `kurly.listOf([...])`, which drops `null` entries and
flattens nested arrays — so `if cond then manifest` (null when false) and nested
groups compose cleanly. `kurly.join` is the same drop-and-flatten over a plain
array.

## The docs are the source of truth

The current documentation is at <https://kurly.projects.metio.wtf/>, with a
machine-readable index at `/llms.txt` and the whole site at `/llms-full.txt`.
For an exact feature, parameter, type, or default, prefer these over memory:

- **[Reference](https://kurly.projects.metio.wtf/reference/)** — every kind,
  feature, exposure recipe, and security profile with its parameters.
- **[`/catalog.json`](https://kurly.projects.metio.wtf/catalog.json)** — the same
  data, machine-readable (schemaVersion, kinds, features, expose, security,
  workloads). Fetch and parse this when you need the precise API.
- **[Assembler](https://kurly.projects.metio.wtf/assembler/)** — compose a
  workload in the browser and copy out the snippet + JaaS manifests.

## Base kinds

- `kurly.http(name, image)` — a Deployment (2 replicas) **and** a ClusterIP
  Service. The only kind you can expose.
- `kurly.worker(name, image)` — a Deployment, no Service. Reaches out rather than
  serving.
- `kurly.cron(name, image, schedule)` — a CronJob.
- `kurly.daemon(name, image)` — a DaemonSet (one pod per node).

## Composition rules to honor

- **A feature contributes only to `config`.** Never patch a manifest field from a
  feature — a later feature that recomputes that manifest from config would
  clobber it.
- **One exposure per workload.** Every `kurly.expose.*` recipe joins the
  `exposure` exclusion group; composing two fails the render. Exposure also
  requires a Service, so it only composes onto `kurly.http` — composing onto a
  worker/cron/daemon fails with a `requiresService` assert.
- **Security profiles set every knob, last one wins.** `kurly.security.restricted`
  (the default, written out), `.baseline`, and `.privileged` each set all
  security knobs, so compose a profile *before* the single-knob hatches
  (`kurly.rootUser`, `kurly.writableRootFilesystem`, `kurly.hostUsers`) that
  fine-tune it. A relaxed knob omits its field rather than writing the default.
- **A ReadWriteOnce store needs `kurly.recreate()`.** A rolling update would
  deadlock on the volume, so a single-writer workload with a `kurly.store` should
  use the Recreate strategy and one replica.
- **User labels never reach a selector.** `kurly.labels` adds to metadata and the
  pod template only; the immutable `matchLabels` stay stable.

## Starting from a published workload

Deployable workloads live under `workloads/<name>/` as one `function(params)`
stage per file — a composable base with defaults and no exposure. Import a stage
by its canonical path, add your environment's `+` features, and render:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tik = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';

kurly.list(
  tik()                                             // the workload's composable base
  + kurly.expose.gateway('tik.internal', 'shared')  // route it at your host
  + kurly.store('/var/lib/tik', '5Gi')              // any feature composes
)
```

## Rendering locally

kurly imports k8s-libsonnet, which is vendored on demand and gitignored:

```sh
jb install                                    # vendor k8s-libsonnet
# resolve kurly's own canonical import path locally:
mkdir -p vendor/github.com/metio && ln -sfn ../../.. vendor/github.com/metio/kurly
jsonnet -J vendor your-workload.jsonnet       # renders the kind: List
```

Author a workload as `function(params) …` so JaaS can feed parameters as TLAs;
plain `jsonnet` renders the defaults.

## Deploying through JaaS + stageset

kurly ships its **source** (not rendered manifests) as single-layer OCI images.
A consumer pulls them as Flux `OCIRepository` sources, imports the workload by
canonical path in a `JsonnetSnippet`, composes their features, and renders with
`kurly.list`; stageset-controller applies the result. See
[references/reference.md](references/reference.md) for the full manifest set, or
generate it from the Assembler.
