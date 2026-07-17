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
local allKinds = ['http', 'worker', 'cron', 'daemon', 'stateful', 'job'];
// The Deployment-backed kinds — the only ones with an update strategy or an HPA
// that scales a Deployment (cron/job run to completion, daemon runs one pod per
// node, stateful is a StatefulSet).
local deploymentKinds = ['http', 'worker'];
// The kinds with a replica count (Deployments and the StatefulSet).
local replicatedKinds = ['http', 'worker', 'stateful'];

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
    stateful: d.fn('A workload with stable identity and per-pod storage: a StatefulSet plus the headless Service that names it. The store feature renders as a per-pod volumeClaimTemplate.', [
      d.arg('name', d.T.string, required=true, example='postgres'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/postgres:16'),
    ]) + { hasService: true },
    job: d.fn('A one-off task that runs to completion: a Job with restartPolicy OnFailure. No Service, no replicas.', [
      d.arg('name', d.T.string, required=true, example='db-migrate'),
      d.arg('image', d.T.string, required=true, example='ghcr.io/acme/migrate:1.2.3'),
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
    ]) + { kinds: replicatedKinds, group: 'container' },
    args: d.fn("Appends arguments to the image's own entrypoint — typically a subcommand selecting the workload.", [
      d.arg('args', d.T.array, required=true, example=['backend', '--config=/etc/tik/pipelines.edn']),
    ]) + { kinds: allKinds, group: 'container' },
    command: d.fn('Overrides the image entrypoint entirely.', [
      d.arg('command', d.T.array, required=true, example=['/bin/app']),
    ]) + { kinds: allKinds, group: 'container' },
    env: d.fn('Environment variables as a name→value map, appended to the container.', [
      d.arg('env', d.T.object, required=true, example={ LOG_LEVEL: 'info' }),
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
    podLabels: d.fn('Labels on the pod template ONLY (never the workload metadata or the immutable selector) — for network-policy selectors and log collection.', [
      d.arg('podLabels', d.T.object, required=true, example={ tier: 'database' }),
    ]) + { kinds: allKinds, group: 'container' },
    podAnnotations: d.fn('Annotations on the pod template ONLY — for sidecar injection and scrape hints that are meaningless on the controller object.', [
      d.arg('podAnnotations', d.T.object, required=true, example={ 'linkerd.io/inject': 'enabled' }),
    ]) + { kinds: allKinds, group: 'container' },
    imagePullSecrets: d.fn('Names of existing Secrets the kubelet uses to pull the image.', [
      d.arg('names', d.T.array, required=true, example=['regcred']),
    ]) + { kinds: allKinds, group: 'container' },
    priorityClassName: d.fn("The pod's scheduling priority class.", [
      d.arg('priorityClassName', d.T.string, required=true, example='high-priority'),
    ]) + { kinds: allKinds, group: 'container' },
    runtimeClassName: d.fn('The sandbox the pod runs under (gVisor, Kata). The class names belong to the cluster, so there is no default — a workload that cannot name one cannot run where sandboxing is mandatory.', [
      d.arg('runtimeClassName', d.T.string, required=true, example='gvisor'),
    ]) + { kinds: allKinds, group: 'container' },
    resources: d.fn('Container resource requests and/or limits.', [
      d.arg('requests', d.T.object, example={ cpu: '100m', memory: '128Mi' }),
      d.arg('limits', d.T.object, example={ memory: '256Mi' }),
    ]) + { kinds: allKinds, group: 'container' },
    resourcePreset: d.fn('A named resource size (nano/micro/small/medium/large) — a memory request equal to its limit and a CPU request with no limit. Replaces resources wholesale.', [
      d.arg('preset', d.T.string, required=true, example='small'),
    ]) + { kinds: allKinds, group: 'container' },
    servicePort: d.fn('The port the Service publishes — the contract with clients, which the container port need not match.', [
      d.arg('port', d.T.int, required=true, example=443),
    ]) + { kinds: ['http'], group: 'container' },
    serviceType: d.fn('The Service type. LoadBalancer and NodePort exist only where the cluster provides them, so there is no default.', [
      d.arg('type', d.T.string, required=true, example='LoadBalancer'),
    ]) + { kinds: ['http'], group: 'container' },
    serviceAnnotations: d.fn('Annotations on the Service. A cloud load balancer is configured through these and nothing else, and the keys differ per provider — without them a LoadBalancer cannot be shaped on any managed cloud.', [
      d.arg('annotations', d.T.object, required=true, example={ 'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb' }),
    ]) + { kinds: ['http'], group: 'container' },
    ipFamilies: d.fn('The IP families EVERY Service the workload renders asks for. A cluster is single-stack IPv4, single-stack IPv6, or dual-stack; pinning a family it lacks gets the Service rejected, so kurly names none and lets the cluster decide.', [
      d.arg('families', d.T.array, required=true, example=['IPv4', 'IPv6']),
      d.arg('policy', d.T.string, example='RequireDualStack'),
    ]) + { kinds: allKinds, group: 'container' },
    serviceAccount: d.fn("Runs the pod under a named ServiceAccount (also gates token automount). Yours wins over the one a workload's RBAC would mint, and kurly then mints none — the account is yours to own and annotate.", [
      d.arg('serviceAccountName', d.T.string, required=true, example='storefront'),
    ]) + { kinds: allKinds, group: 'container' },
    serviceAccountAnnotations: d.fn('Annotations for the ServiceAccount kurly mints for a workload that declares RBAC — where cloud workload identity is wired (eks.amazonaws.com/role-arn, iam.gke.io/gcp-service-account). Moot when you bring your own account with serviceAccount().', [
      d.arg('annotations', d.T.object, required=true, example={ 'eks.amazonaws.com/role-arn': 'arn:aws:iam::123456789012:role/storefront' }),
    ]) + { kinds: allKinds, group: 'container' },
    probes: d.fn('HTTP readiness and liveness probes on the named http port.', [
      d.arg('path', d.T.path, default='/healthz', example='/tickets.edn'),
    ]) + { kinds: ['http'], group: 'container' },
    readinessProbe: d.fn('An explicit readiness probe spec (exec/tcpSocket/httpGet), overriding the default http probe.', [
      d.arg('probe', d.T.object, required=true, example={ exec: { command: ['sh', '-c', 'valkey-cli ping'] } }),
    ]) + { kinds: allKinds, group: 'container' },
    livenessProbe: d.fn('An explicit liveness probe spec (exec/tcpSocket/httpGet), overriding the default http probe.', [
      d.arg('probe', d.T.object, required=true, example={ tcpSocket: { port: 6379 } }),
    ]) + { kinds: allKinds, group: 'container' },
    lifecycle: d.fn('Container lifecycle handlers (postStart / preStop), passed through verbatim.', [
      d.arg('preStop', d.T.object, example={ exec: { command: ['sh', '-c', 'valkey-cli failover'] } }),
      d.arg('postStart', d.T.object),
    ]) + { kinds: allKinds, group: 'container' },
    sidecar: d.fn("An extra container beside the workload's own, sharing the pod. It inherits the composed security posture unless it carries its own securityContext — so a sidecar does not restate a uid, and does not silently keep one when the consumer changes it.", [
      d.arg('container', d.T.object, required=true, example={ name: 'agent', image: 'ghcr.io/acme/agent:1.0' }),
    ]) + { kinds: allKinds, group: 'container' },
    initContainer: d.fn('An init container run to completion before the main one — the full container spec, passed through. Composes more than once.', [
      d.arg('container', d.T.object, required=true, example={ name: 'setup', image: 'busybox:1', command: ['sh', '-c', 'echo ready'] }),
    ]) + { kinds: allKinds, group: 'container' },
    terminationGracePeriod: d.fn("How long the pod gets to shut down gracefully (a preStop hook's window).", [
      d.arg('seconds', d.T.int, required=true, example=120),
    ]) + { kinds: allKinds, group: 'container' },
    rollingUpdate: d.fn('RollingUpdate tuning so a new pod surges alongside the old during an update — the overlap a replication hand-off needs.', [
      d.arg('maxSurge', d.T.any, example=1),
      d.arg('maxUnavailable', d.T.any),
    ]) + { kinds: deploymentKinds, group: 'container' },

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

    // Pod placement — merged onto the pod template verbatim.
    nodeSelector: d.fn('Restricts the pod to nodes carrying these labels.', [
      d.arg('nodeSelector', d.T.object, required=true, example={ disktype: 'ssd' }),
    ]) + { kinds: allKinds, group: 'placement' },
    tolerations: d.fn('Tolerations letting the pod schedule onto tainted nodes.', [
      d.arg('tolerations', d.T.array, required=true, example=[{ key: 'gpu', operator: 'Exists', effect: 'NoSchedule' }]),
    ]) + { kinds: allKinds, group: 'placement' },
    topologySpread: d.fn('Topology-spread constraints spreading the pods across a topology domain (keep version-bound labels in the selector so a rollout spreads the new set independently).', [
      d.arg('constraints', d.T.array, required=true, example=[{ maxSkew: 1, topologyKey: 'kubernetes.io/hostname', whenUnsatisfiable: 'DoNotSchedule', labelSelector: { matchLabels: { 'app.kubernetes.io/name': 'web' } } }]),
    ]) + { kinds: allKinds, group: 'placement' },
    affinity: d.fn('A pod/node affinity object, merged onto the pod template.', [
      d.arg('affinity', d.T.object, required=true, example={ nodeAffinity: { requiredDuringSchedulingIgnoredDuringExecution: { nodeSelectorTerms: [{ matchExpressions: [{ key: 'disktype', operator: 'In', values: ['ssd'] }] }] } } }),
    ]) + { kinds: allKinds, group: 'placement' },

    // Owned manifests — each adds a resource that targets the workload's pods.
    pdb: d.fn('A PodDisruptionBudget capping voluntary disruption. Set one of minAvailable / maxUnavailable.', [
      d.arg('minAvailable', d.T.any, example=1),
      d.arg('maxUnavailable', d.T.any),
    ]) + { kinds: ['http', 'worker', 'daemon', 'stateful'], group: 'reliability' },
    hpa: d.fn('A HorizontalPodAutoscaler scaling the Deployment on CPU and/or memory utilization.', [
      d.arg('minReplicas', d.T.int, required=true, example=2),
      d.arg('maxReplicas', d.T.int, required=true, example=10),
      d.arg('targetCPU', d.T.int, example=80),
      d.arg('targetMemory', d.T.int),
    ]) + { kinds: deploymentKinds, group: 'reliability' },
    networkPolicy: d.fn('A NetworkPolicy firewalling the pods (ingress/egress rules and policyTypes passed through verbatim).', [
      d.arg('ingress', d.T.array, default=[]),
      d.arg('egress', d.T.array, default=[]),
      d.arg('policyTypes', d.T.array),
    ]) + { kinds: allKinds, group: 'networking' },
    headlessService: d.fn('A headless Service (clusterIP: None) selecting the pods, for DNS peer discovery — the discovery a replication hand-off needs.', [
      d.arg('port', d.T.int, example=6379),
      d.arg('publishNotReady', d.T.bool, default=false),
    ]) + { kinds: ['http', 'worker', 'daemon', 'stateful'], group: 'networking' },
    serviceMonitor: d.fn('A Prometheus-Operator ServiceMonitor scraping the workload Service.', [
      d.arg('port', d.T.string, default='http'),
      d.arg('path', d.T.path, default='/metrics'),
      d.arg('interval', d.T.string),
    ]) + { kinds: ['http'], group: 'observability' },
    rbac: d.fn('Mints a ServiceAccount, a namespaced Role with the given rules, and the RoleBinding, and runs the pod under that ServiceAccount.', [
      d.arg('rules', d.T.array, required=true, example=[{ apiGroups: [''], resources: ['configmaps'], verbs: ['get', 'list', 'watch'] }]),
    ]) + { kinds: allKinds, group: 'security' },
    apiServerClient: d.fn('Declares a pod as a Kubernetes API client: adds the given Role rules AND best-effort NetworkPolicy egress to the apiserver, both as cross-cutting requirements that compose with (never clobber) a consumer own rbac()/networkPolicy().', [
      d.arg('rules', d.T.array, required=true, example=[{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }]),
      d.arg('ports', d.T.array, default=[443, 6443]),
    ]) + { kinds: allKinds, group: 'security' },
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
    'cnpg-cluster': {
      summary: 'A highly-available PostgreSQL cluster as a CloudNativePG Cluster custom resource (three instances, a bootstrapped database, a PodMonitor). Requires the CloudNativePG operator.',
      stages: {
        cluster: d.fn('The PostgreSQL Cluster CR. Adapt it with the parameters and render with kurly.list — composed by parameter, not by + feature (it is a custom resource, not a base kind). Point it at a cnpg-image-catalog with catalog/major to keep the image choice in one place, or pin imageName directly; the two are mutually exclusive.', [
          d.arg('name', d.T.string, default='postgres'),
          d.arg('instances', d.T.int, default=3),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('database', d.T.string, default='app'),
          d.arg('labels', d.T.object, default={}, example={ team: 'payments' }),
          d.arg('annotations', d.T.object, default={}),
          d.arg('affinity', d.T.object, example={ nodeSelector: { workload: 'database' }, podAntiAffinityType: 'required' }),
          d.arg('topologySpreadConstraints', d.T.array, default=[]),
          d.arg('priorityClassName', d.T.string),
        ]) + {
          kind: 'cnpg',
          importPath: 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet',
        },
      },
    },
    'cnpg-image-catalog': {
      summary: 'The PostgreSQL images a fleet of CloudNativePG clusters may run, as an ImageCatalog or ClusterImageCatalog custom resource — one image per major, so a patch bump is one line and rolls every cluster on that major. Requires the CloudNativePG operator.',
      stages: {
        namespaced: d.fn('A namespaced ImageCatalog, owned by the team that owns the databases. Keys of `images` are PostgreSQL major versions; a cnpg-cluster pins one with catalog/major and the catalog owns the patch.', [
          d.arg('name', d.T.string, default='postgres'),
          d.arg('images', d.T.object, default={ '17': 'ghcr.io/cloudnative-pg/postgresql:17.2' }),
        ]) + {
          kind: 'cnpg',
          importPath: 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet',
        },
        cluster: d.fn('A cluster-scoped ClusterImageCatalog, serving every namespace from one object. Identical spec to the namespaced stage; a cnpg-cluster points at it with catalogScope=cluster.', [
          d.arg('name', d.T.string, default='postgres'),
          d.arg('images', d.T.object, default={ '17': 'ghcr.io/cloudnative-pg/postgresql:17.2' }),
        ]) + {
          kind: 'cnpg',
          importPath: 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet',
        },
      },
    },
    dragonfly: {
      summary: "A RESP-speaking in-memory store with a per-pod PVC and a headless Service. Answers the same protocol as Valkey, but is not a fork of it: it rejects Redis flags, persists through snapshots, and runs one io thread per core it can see — which in a container is the node's, so the thread count is pinned and the memory floor it demands (256MiB per thread) is asserted at render.",
      stages: {
        instance: d.fn('The Dragonfly server. threads pins --proactor_threads and sizes the CPU (Dragonfly runs a thread per core); maxMemoryMB must be at least 256 per thread or Dragonfly exits at startup, so the render fails first. Name it for its role and a consumer never learns which RESP store it got.', [
          d.arg('name', d.T.string, default='dragonfly'),
          d.arg('image', d.T.string, default='ghcr.io/dragonflydb/dragonfly:v1.39.0'),
          d.arg('maxMemoryMB', d.T.int, default=512),
          d.arg('threads', d.T.int, default=2),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet',
        },
      },
    },
    memcached: {
      summary: "An in-memory cache sharded by the client, as a StatefulSet whose storage is nothing and whose identity is everything. No replication and no persistence: an upgrade always starts cold, and stable pod names are what bound the loss to 1/N of a client's keyspace.",
      stages: {
        cache: d.fn('The memcached shards: a StatefulSet (for stable DNS names, not storage) and the headless Service that names them. Clients consistent-hash keys over memcached-0..N-1; scaling reshuffles that ring, so treat replicas as part of the client configuration. The container memory limit is derived from memoryMB, since -m caps only the item cache.', [
          d.arg('image', d.T.string, default='docker.io/library/memcached:1.6.45'),
          d.arg('replicas', d.T.int, default=3),
          d.arg('memoryMB', d.T.int, default=64),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/memcached/cache.libsonnet',
        },
      },
    },
    valkey: {
      summary: 'A persistent Valkey server (the BSD Redis fork) on the official upstream image, as a kurly.stateful workload with a per-pod PVC and a headless Service. Single-instance stage; a Redis-compatible alternative runs by overriding the image.',
      stages: {
        instance: d.fn('The single-instance Valkey server: a StatefulSet with append-only persistence into a volumeClaimTemplate. Compose + features as usual (it is a composable kurly.stateful app). `image` also accepts a Redis build — Valkey is its BSD fork and takes the same configuration — so name the workload for its role rather than its engine, and a consumer holding an endpoint never learns which it got.', [
          d.arg('name', d.T.string, default='valkey'),
          d.arg('image', d.T.string, default='docker.io/valkey/valkey:9.0.3'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/valkey/instance.libsonnet',
        },
        cache: d.fn('An in-memory Valkey cache that upgrades its version with zero downtime and no data loss, on the stock image and no orchestrator — the replication hand-off lives entirely in the pod manifests (headless Service, maxSurge, an initContainer that replicates the running peer, and a preStop failover).', [
          d.arg('image', d.T.string, default='docker.io/valkey/valkey:9.0.3'),
          d.arg('maxMemory', d.T.string, default='256mb'),
        ]) + {
          kind: 'worker',
          importPath: 'github.com/metio/kurly/workloads/valkey/cache.libsonnet',
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
    mirror: d.fn("Points every image in already-rendered manifests at another registry, for a cluster that pulls from a private one. Rewrites the rendered output, not config: an initContainer, a grafted-on sidecar and a custom resource's image are all unreachable from config, so a config-level knob would redirect the main container and leave the rest pulling from the internet. Only the registry (the first path segment) changes; repository, tag and digest are untouched.", [
      d.arg('registry', d.T.string, required=true, example='harbor.internal/dockerhub'),
      d.arg('manifests', d.T.object, required=true),
    ]),
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
