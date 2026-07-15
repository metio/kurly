// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The public-API annotations for kurly's kinds, features, exposure recipes, and
// security profiles — the editorial layer a docs tool and the assembler catalog
// both read. Structural truth (which features exist) is cross-checked against
// the real modules by catalog.jsonnet, which fails if this map and the exported
// fields ever diverge; what lives here is the prose, parameter types, examples,
// and kurly's own composition facets (a feature's legal kinds, its exclusion
// group, whether it needs a Service).
local d = import './docs.libsonnet';

// Every workload kind, for features with no kind-specific constraint.
local allKinds = ['http', 'worker', 'cron', 'daemon'];
// The Deployment-backed kinds — the only ones with replicas or an update
// strategy (cron runs Jobs, daemon runs one pod per node).
local deploymentKinds = ['http', 'worker'];

{
  // Base kinds — each a `function(...)` you start from and add features onto.
  kinds: {
    http: d.fn('An HTTP workload: a Deployment (2 replicas) and a ClusterIP Service. Compose an exposure feature to accept traffic from outside the cluster.', [
      d.arg('name', d.T.string, required=true, example='storefront'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/storefront:1.2.3'),
    ]) + { hasService: true },
    worker: d.fn('A background worker: a Deployment with no Service. Reaches out (queues, schedules) rather than serving traffic.', [
      d.arg('name', d.T.string, required=true, example='indexer'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/indexer:1.2.3'),
    ]) + { hasService: false },
    cron: d.fn('A scheduled job: a CronJob that runs to completion on a cron schedule.', [
      d.arg('name', d.T.string, required=true, example='nightly-report'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/report:1.2.3'),
      d.arg('schedule', d.T.string, required=true, example='0 2 * * *'),
    ]) + { hasService: false },
    daemon: d.fn('A per-node agent: a DaemonSet running one pod on every node.', [
      d.arg('name', d.T.string, required=true, example='node-exporter'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/node-agent:1.2.3'),
    ]) + { hasService: false },
  },

  // Composable capabilities. `group` buckets the palette; `kinds` is the
  // advisory legality (the render-time asserts enforce the hard constraints).
  features: {
    // Container basics.
    image: d.fn('Overrides the container image.', [
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/app:1.2.3'),
    ]) + { kinds: allKinds, group: 'container' },
    port: d.fn('The container port the workload listens on (also the Service target).', [
      d.arg('port', d.T.int, required=true, example=8080),
    ]) + { kinds: ['http'], group: 'container' },
    replicas: d.fn('The desired number of pod replicas.', [
      d.arg('replicas', d.T.int, required=true, example=3),
    ]) + { kinds: deploymentKinds, group: 'container' },
    args: d.fn("Appends arguments to the image's own entrypoint — typically a subcommand selecting the workload.", [
      d.arg('args', d.T.array, required=true, example=['backend', '--config=/etc/tik/pipelines.edn']),
    ]) + { kinds: allKinds, group: 'container' },
    command: d.fn('Overrides the image entrypoint entirely.', [
      d.arg('command', d.T.array, required=true, example=['/bin/app']),
    ]) + { kinds: allKinds, group: 'container' },
    env: d.fn('Appends environment variables (k8s EnvVar entries) to the container.', [
      d.arg('env', d.T.array, required=true, example=[{ name: 'LOG_LEVEL', value: 'info' }]),
    ]) + { kinds: allKinds, group: 'container' },
    version: d.fn('The workload version, stamped as app.kubernetes.io/version on every object.', [
      d.arg('version', d.T.string, required=true, example='1.2.3'),
    ]) + { kinds: allKinds, group: 'container' },
    labels: d.fn('Extra labels on metadata and the pod template (never on immutable selectors).', [
      d.arg('labels', d.T.object, required=true, example={ team: 'payments' }),
    ]) + { kinds: allKinds, group: 'container' },
    annotations: d.fn('Extra annotations on metadata and the pod template.', [
      d.arg('annotations', d.T.object, required=true, example={ 'prometheus.io/scrape': 'true' }),
    ]) + { kinds: allKinds, group: 'container' },
    resources: d.fn('Container resource requests and/or limits.', [
      d.arg('requests', d.T.object, example={ cpu: '100m', memory: '128Mi' }),
      d.arg('limits', d.T.object, example={ memory: '256Mi' }),
    ]) + { kinds: allKinds, group: 'container' },
    serviceAccount: d.fn('Runs the pod under a named ServiceAccount (also gates token automount).', [
      d.arg('serviceAccountName', d.T.string, required=true, example='storefront'),
    ]) + { kinds: allKinds, group: 'container' },
    probes: d.fn('HTTP readiness and liveness probes on the named http port.', [
      d.arg('path', d.T.path, default='/healthz', example='/tickets.edn'),
    ]) + { kinds: ['http'], group: 'container' },

    // Scheduling (CronJob tuning — only kurly.cron reads these).
    schedule: d.fn('The cron schedule expression.', [
      d.arg('schedule', d.T.string, required=true, example='0 2 * * *'),
    ]) + { kinds: ['cron'], group: 'scheduling' },
    concurrencyPolicy: d.fn('How to treat a job that is still running when the next is due (Allow/Forbid/Replace).', [
      d.arg('concurrencyPolicy', d.T.string, required=true, example='Forbid'),
    ]) + { kinds: ['cron'], group: 'scheduling' },

    // Storage and mounts.
    store: d.fn("The workload's own PersistentVolumeClaim, mounted at a path.", [
      d.arg('mountPath', d.T.path, required=true, example='/var/lib/tik'),
      d.arg('size', d.T.quantity, required=true, example='1Gi'),
      d.arg('accessModes', d.T.array, default=['ReadWriteOnce']),
      d.arg('storageClass', d.T.string),
      d.arg('selector', d.T.object),
      d.arg('annotations', d.T.object),
    ]) + { kinds: allKinds, group: 'storage' },
    config: d.fn('Renders a ConfigMap from a filename→content map and mounts it read-only.', [
      d.arg('files', d.T.object, required=true, example={ 'app.conf': 'key = value' }),
      d.arg('mountPath', d.T.path, default='/etc/config'),
    ]) + { kinds: allKinds, group: 'storage' },
    secretMount: d.fn('Mounts an EXISTING Secret (kurly never mints key material).', [
      d.arg('secretName', d.T.string, required=true, example='tik-tls'),
      d.arg('mountPath', d.T.path, required=true, example='/etc/tls'),
      d.arg('readOnly', d.T.bool, default=true),
      d.arg('optional', d.T.bool, default=false),
      d.arg('defaultMode', d.T.int),
    ]) + { kinds: allKinds, group: 'storage' },
    scratch: d.fn('A writable emptyDir — the escape valve a read-only root filesystem needs for /tmp and the like.', [
      d.arg('mountPath', d.T.path, required=true, example='/tmp'),
      d.arg('sizeLimit', d.T.quantity),
    ]) + { kinds: allKinds, group: 'storage' },

    // Security escape hatches (each downgrades one default; compose after a
    // security profile).
    runAs: d.fn('Pins the run-as user/group (and matching fsGroup) for images that do not declare a non-root USER.', [
      d.arg('uid', d.T.int, required=true, example=12345),
      d.arg('gid', d.T.int),
      d.arg('fsGroup', d.T.int),
    ]) + { kinds: allKinds, group: 'security' },
    rootUser: d.fn('Allows the container to run as root (relaxes runAsNonRoot).', []) + { kinds: allKinds, group: 'security' },
    writableRootFilesystem: d.fn('Makes the root filesystem writable (relaxes readOnlyRootFilesystem).', []) + { kinds: allKinds, group: 'security' },
    hostUsers: d.fn('Shares the host user namespace (relaxes hostUsers=false).', []) + { kinds: allKinds, group: 'security' },

    // Update strategy.
    strategy: d.fn('The Deployment update strategy.', [
      d.arg('strategy', d.T.string, required=true, example='RollingUpdate'),
    ]) + { kinds: deploymentKinds, group: 'container' },
    recreate: d.fn('The single-writer strategy: tears the old pod down before starting the new one, so a ReadWriteOnce store never deadlocks a rollout.', []) + { kinds: deploymentKinds, group: 'container' },
  },

  // Exposure recipes — a separate axis, composed onto an http workload. All
  // join the `exposure` exclusion group (one exposure per workload) and require
  // a Service.
  expose: {
    ingress: d.fn('Routes the host to the workload through the Ingress API.', [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('ingressClass', d.T.string),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    gateway: d.fn('Attaches an HTTPRoute to an existing shared Gateway (the usual platform-team setup).', [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('gateway', d.T.string, required=true, example='shared'),
      d.arg('gatewayNamespace', d.T.string),
      d.arg('sectionName', d.T.string),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    listenerSet: d.fn('Attaches an HTTPRoute to an existing ListenerSet (per-tenant listener ownership).', [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('listenerSet', d.T.string, required=true, example='tenant-a'),
      d.arg('listenerSetNamespace', d.T.string),
      d.arg('sectionName', d.T.string),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    ownGateway: d.fn('Generates a dedicated Gateway plus the HTTPRoute — for clusters with no shared Gateway to attach to.', [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('gatewayClass', d.T.string, required=true, example='istio'),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    ownListenerSet: d.fn("Generates a ListenerSet that adds the workload's own listener to a shared Gateway, plus the HTTPRoute. The Gateway must opt in via spec.allowedListeners.", [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('gateway', d.T.string, required=true, example='shared'),
      d.arg('gatewayNamespace', d.T.string),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
  },

  // Pod Security Standards profiles — a mixin that relaxes the default
  // `restricted` posture. The last profile composed wins; single-knob hatches
  // fine-tune after it.
  security: {
    restricted: d.fn('The default posture, written out. Compose after another profile to re-tighten.', []),
    baseline: d.fn('Relaxes what only restricted requires (root allowed, default capabilities kept, privilege escalation and unpinned seccomp permitted); keeps the read-only root filesystem and user namespaces.', []),
    privileged: d.fn('Emits no security fields at all — the manifest constrains nothing.', []),
  },

  // Deployable workloads — the starting point the assembler composes onto. Each
  // stage is a `function(params)` app (a base kind with defaults, no exposure); a
  // consumer imports it by its canonical path, adds `+` features (chiefly an
  // exposure recipe), and renders with kurly.list. `kind` is the base the stage
  // builds on, so the UI knows which features are legal; `importPath` is the path
  // the snippet imports. catalog.jsonnet asserts each importPath resolves to a
  // function.
  workloads: {
    tik: {
      summary: "A lightweight ticket board and release supervisor. One process serves a read-only board and runs the store's writers over a shared append-only event store.",
      stages: {
        backend: d.fn('The tik backend supervisor: a single-writer http app over a ReadWriteOnce store (one replica, recreated to avoid deadlocking on the volume). Compose an exposure recipe to serve the board.', [
          d.arg('image', d.T.string, default='ghcr.io/metio/tik:2026.7.14194001'),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/tik/backend.libsonnet',
        },
      },
    },
  },

  // The stageset-controller migration-ladder builder.
  migrations: {
    migration: d.fn('Builds one entry of a stageset-controller migration ladder (a plain array of these). Actions are passed through verbatim.', [
      d.arg('name', d.T.string, required=true, example='2026.5.25'),
      d.arg('to', d.T.string, required=true, example='2026.5.25'),
      d.arg('from', d.T.string),
      d.arg('stage', d.T.string),
      d.arg('actions', d.T.array),
    ]),
  },

  // Rendering terminals — turn a composed app or an explicit set of parts into
  // the output a consumer applies or publishes.
  helpers: {
    list: d.fn('Renders one composed app as a kind: List, including its hidden owned manifests (the store PVC, the config ConfigMap).', [
      d.arg('app', d.T.object, required=true),
    ]),
    listOf: d.fn('Renders an explicit set of parts as a kind: List. Joins the parts first, so entries can be null (dropped) or nested arrays (flattened) — build the set with conditionals and optional groups.', [
      d.arg('parts', d.T.array, required=true),
    ]),
    join: d.fn('Builds one flat array from parts that may be null (dropped) or nested arrays (flattened one level), for assembling any value with conditionals and optional groups. A Jsonnet `if` with no else is null when false, so an unmet condition drops out.', [
      d.arg('parts', d.T.array, required=true),
    ]),
  },
}
