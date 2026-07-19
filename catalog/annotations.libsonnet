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
    envFromSecret: d.fn('Pull every key of an EXISTING Secret into the environment (envFrom secretRef); kurly mints no Secret. An optional prefix is prepended to each variable name.', [
      d.arg('secretName', d.T.string, required=true, example='mailu-secrets'),
      d.arg('prefix', d.T.string),
    ]) + { kinds: allKinds, group: 'container' },
    envFromConfigMap: d.fn('Pull every key of an EXISTING ConfigMap into the environment (envFrom configMapRef). An optional prefix is prepended to each variable name.', [
      d.arg('configMapName', d.T.string, required=true, example='app-config'),
      d.arg('prefix', d.T.string),
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
    dns: d.fn("Pod name resolution: a resolver policy, extra nameservers/searches/options, and static /etc/hosts entries for names no DNS serves. dnsPolicy 'None' takes resolv.conf entirely from config, so it must bring its own nameservers — a render-time check enforces that.", [
      d.arg('policy', d.T.string, example='None'),
      d.arg('config', d.T.object, example={ nameservers: ['10.0.0.10'], searches: ['corp.local'] }),
      d.arg('hostAliases', d.T.array, example=[{ ip: '10.0.0.5', hostnames: ['db.internal'] }]),
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
    rootUser: d.fn('Drops runAsNonRoot so the container may run as the image USER; add runAs(0) to pin uid 0.', []) + { kinds: allKinds, group: 'security' },
    writableRootFilesystem: d.fn('Makes the root filesystem writable (relaxes readOnlyRootFilesystem).', []) + { kinds: allKinds, group: 'security' },
    hostUsers: d.fn('Shares the host user namespace instead of an own one — needed on Windows nodes and where user namespaces are unavailable (relaxes hostUsers=false).', []) + { kinds: allKinds, group: 'security' },
    supplementalGroups: d.fn("Extra group memberships for every container in the pod — how a pod reaches storage owned by a fixed GID it does not run as (a shared NFS/CephFS export). Distinct from fsGroup, which changes ownership of the pod's own volumes.", [
      d.arg('groups', d.T.array, required=true, example=[2000]),
    ]) + { kinds: allKinds, group: 'security' },

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
      d.arg('ingressClass', d.T.string, example='nginx'),
      d.arg('annotations', d.T.object, default={}, example={ 'cert-manager.io/cluster-issuer': 'letsencrypt' }),
      d.arg('tls', d.T.string, example='storefront-tls'),
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
      d.arg('annotations', d.T.object, default={}, example={ 'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb' }),
      d.arg('tls', d.T.string, example='storefront-tls'),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    ownListenerSet: d.fn("Generates a ListenerSet that adds the workload's own listener to a shared Gateway, plus the HTTPRoute. The Gateway must opt in via spec.allowedListeners.", [
      d.arg('host', d.T.hostname, required=true, example='storefront.example.com'),
      d.arg('gateway', d.T.string, required=true, example='shared'),
      d.arg('gatewayNamespace', d.T.string),
      d.arg('tls', d.T.string, example='storefront-tls'),
    ]) + { kinds: ['http'], exclusiveGroup: 'exposure', requiresService: true },
    guard: d.fn('Sinks specific path prefixes on the HTTPRoute to a status-responder Service instead of the workload — the portable way to take a path off the public internet (answer 403/404) while the workload stays reachable in-cluster. A modifier composed after a Gateway API exposure, not an exposure itself; a cross-namespace responder needs a ReferenceGrant on that side. Compose it more than once to sink different paths to different responders.', [
      d.arg('paths', d.T.array, required=true, example=['/admin', '/stats']),
      d.arg('service', d.T.string, required=true, example='not-found'),
      d.arg('serviceNamespace', d.T.string, example='shared-http-services'),
      d.arg('port', d.T.int, default=5678),
    ]) + { kinds: ['http'], requiresExposure: true },
    referenceGrant: d.fn("Lets HTTPRoutes in other namespaces route to this workload's Service — the cross-namespace consent Gateway API requires, granted on the Service side and naming the allowed namespaces. Deploy a shared status-responder once, grant the tenant namespaces, and their guard rules can target its Service. A modifier, not an exposure.", [
      d.arg('fromNamespaces', d.T.array, required=true, example=['team-a', 'team-b']),
    ]) + { kinds: ['http'], requiresService: true },
    dns: d.fn('Adds external-dns annotations to the exposure resource (the HTTPRoute for a Gateway API recipe, the Ingress for the Ingress one) so external-dns creates the DNS record. A modifier composed after an exposure. external-dns already discovers the exposed hostname, so reach for this to override — a different/additional hostname, a ttl, or a target (the address the record points at). annotations passes through provider-specific keys.', [
      d.arg('hostname', d.T.hostname, example='alias.example.com'),
      d.arg('ttl', d.T.int, example=300),
      d.arg('target', d.T.string, example='ingress.example.net.'),
      d.arg('annotations', d.T.object, default={}),
    ]) + { kinds: ['http'], requiresExposure: true },
    probe: d.fn('Attaches a prometheus-operator Probe to the workload, so Prometheus black-box-monitors its public URL through a blackbox-exporter — the outside-in check that complements the in-cluster ServiceMonitor scrape. A modifier composed onto a workload. host is explicit (target a specific health path, any exposure style); prober is the blackbox-exporter address; module selects its check (http_2xx expects a 2xx).', [
      d.arg('host', d.T.hostname, required=true, example='web.example.com'),
      d.arg('module', d.T.string, default='http_2xx'),
      d.arg('scheme', d.T.string, default='https'),
      d.arg('prober', d.T.string, default='blackbox-exporter:9115'),
      d.arg('proberPath', d.T.string, default='/probe'),
      d.arg('interval', d.T.string, default='30s'),
    ]) + { kinds: ['http'] },
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
    'status-responder': {
      summary: 'A tiny HTTP service that answers every request with one fixed status code and message. Deploy it once, globally, and route protected paths to it from a Gateway API HTTPRoute (kurly.expose.guard) to take them off the public internet — the portable substitute for the fixed-response filter Gateway API lacks.',
      stages: {
        responder: d.fn('One fixed-status responder (hashicorp/http-echo). Pair with kurly.expose.guard on the protected workload and kurly.expose.referenceGrant here for cross-namespace routing.', [
          d.arg('name', d.T.string, default='forbidden'),
          d.arg('statusCode', d.T.int, default=403),
          d.arg('message', d.T.string, default='forbidden'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet',
        },
      },
    },
    tik: {
      summary: "A lightweight ticket board and release supervisor. One process serves a read-only board and runs the store's writers over a shared append-only event store.",
      stages: {
        backend: d.fn('The tik backend supervisor: a single-writer http app over a ReadWriteOnce store (one replica, recreated to avoid deadlocking on the volume). Compose an exposure recipe to serve the board.', [
          d.arg('name', d.T.string, default='tik'),
          d.arg('image', d.T.string, default='ghcr.io/metio/tik:2026.7.18213457'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/tik/backend.libsonnet',
        },
      },
    },
    vaultwarden: {
      summary: 'A Vaultwarden server (a lightweight, Bitwarden-compatible password manager in Rust). A plain composable http workload that keeps its vault, attachments, and JWT signing key in a SQLite database on a PersistentVolume — no external database needed. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web vault and API on :8080.',
      stages: {
        server: d.fn('The Vaultwarden server. domain is the public URL — WebAuthn/passkeys, attachment links, and email all need it. signupsAllowed is off by default (turn on to bootstrap, then off). env carries extra settings (ADMIN_TOKEN, SMTP_*, or DATABASE_URL to move to external Postgres) — the admin token and any DB password should come from a Secret, kurly mints none. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='vaultwarden'),
          d.arg('image', d.T.string, default='docker.io/vaultwarden/server:1.36.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('domain', d.T.string, example='https://vault.example.com'),
          d.arg('signupsAllowed', d.T.bool, default=false),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet',
        },
      },
    },
    endurain: {
      summary: 'An Endurain server (a self-hosted fitness and training-activity tracker) backed by an external PostgreSQL and Redis, with uploads on a PersistentVolume. Pairs with a cnpg-cluster named endurain-db and a valkey named endurain-cache. kurly authors no Secret; DB_PASSWORD and SECRET_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The Endurain server. dbHost/dbName/dbUser default to a cnpg-cluster named endurain-db; redisHost to a valkey named endurain-cache. endurainHost is the public URL. secretName holds DB_PASSWORD and SECRET_KEY (envFrom). Uploads at /app/backend/app on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='endurain'),
          d.arg('image', d.T.string, default='ghcr.io/joaovitoriasilva/endurain:0.17.7'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='endurain-db-rw'),
          d.arg('dbName', d.T.string, default='endurain'),
          d.arg('dbUser', d.T.string, default='endurain'),
          d.arg('redisHost', d.T.string, default='endurain-cache'),
          d.arg('endurainHost', d.T.string, example='https://fitness.example.com'),
          d.arg('secretName', d.T.string, default='endurain-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/endurain/server.libsonnet' },
      },
    },
    seatsurfing: {
      summary: 'A Seatsurfing server (desk and meeting-room booking / hot-desking) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. kurly authors no Secret; POSTGRES_URL and JWT_SIGNING_KEY come from a provided Secret via envFrom. Pairs with a cnpg-cluster named seatsurfing-db. Serves on :8080.',
      stages: {
        server: d.fn('The Seatsurfing server. secretName is the Secret holding POSTGRES_URL (with the embedded DB password) and JWT_SIGNING_KEY, pulled in via envFrom. env carries non-sensitive settings (PUBLIC_URL, FRONTEND_URL). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='seatsurfing'),
          d.arg('image', d.T.string, default='ghcr.io/seatsurfing/seatsurfing:1.116.0'),
          d.arg('secretName', d.T.string, default='seatsurfing-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet' },
      },
    },
    ejabberd: {
      summary: 'An ejabberd server (a robust, scalable XMPP/messaging server) on the official community image. A plain composable http workload that keeps its Mnesia database and uploads on a PersistentVolume — no external database by default. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves XMPP client :5222, s2s :5269, and admin/HTTP :5280; mount ejabberd.yml at /home/ejabberd/conf.',
      stages: {
        server: d.fn('The ejabberd server. Keeps its Mnesia database at /home/ejabberd/database on the volume; mount ejabberd.yml at /home/ejabberd/conf (kurly.config; credentials from a Secret). Route the XMPP ports as TCP and expose :5280 for admin.', [
          d.arg('name', d.T.string, default='ejabberd'),
          d.arg('image', d.T.string, default='docker.io/ejabberd/ecs:26.04'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet' },
      },
    },
    inspircd: {
      summary: 'An InspIRCd server (a modular IRC daemon) on the official image. A plain composable http workload that keeps its runtime data (logs, TLS material) on a PersistentVolume and reads its configuration from a mounted config. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves IRC-over-TLS on :6697; needs an inspircd.conf mounted at /inspircd/conf.',
      stages: {
        server: d.fn('The InspIRCd server. Keeps runtime data at /inspircd/data on the volume; mount its configuration at /inspircd/conf (kurly.config, or a Secret for oper/link credentials). Route the port as TCP.', [
          d.arg('name', d.T.string, default='inspircd'),
          d.arg('image', d.T.string, default='docker.io/inspircd/inspircd-docker:4.11.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/inspircd/server.libsonnet' },
      },
    },
    passwordpusher: {
      summary: 'A Password Pusher server (share passwords and secrets over self-destructing, expiring links) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. kurly authors no Secret; DATABASE_URL and SECRET_KEY_BASE come from a provided Secret via envFrom. Pairs with a cnpg-cluster named passwordpusher-db. Serves on :5100.',
      stages: {
        server: d.fn('The Password Pusher server. secretName is the Secret holding DATABASE_URL (with the embedded DB password) and SECRET_KEY_BASE, pulled in via envFrom; kurly mints none. Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='passwordpusher'),
          d.arg('image', d.T.string, default='docker.io/pglombardo/pwpush:v2.9.3'),
          d.arg('secretName', d.T.string, default='passwordpusher-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet' },
      },
    },
    baikal: {
      summary: 'A Baikal server (a lightweight CalDAV + CardDAV server on sabre/dav) on the maintained ckulka image. A plain composable http workload that keeps its configuration and SQLite database on a PersistentVolume — no external database by default. The nginx + PHP-FPM image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Baikal server. Keeps its SQLite database at /var/www/baikal/Specific and its generated config at /var/www/baikal/config (both on the volume). Point it at external MySQL/PostgreSQL through the setup wizard to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='baikal'),
          d.arg('image', d.T.string, default='docker.io/ckulka/baikal:0.10.1-nginx'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/baikal/server.libsonnet' },
      },
    },
    cryptpad: {
      summary: 'A CryptPad server (end-to-end encrypted, collaborative documents and spreadsheets) on the official image. A plain composable http workload that keeps its encrypted blocks, blobs, and datastore on a PersistentVolume — no external database. The Node app writes under /cryptpad, so it relaxes read-only-rootfs while keeping non-root and dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000; needs a config.js with a main and a separate sandbox origin.',
      stages: {
        server: d.fn('The CryptPad server. Keeps the encrypted datastore at /cryptpad/data on the volume. Mount a config.js (kurly.config) setting httpUnsafeOrigin (main URL) and httpSafeOrigin (a SEPARATE sandbox domain, required for security). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='cryptpad'),
          d.arg('image', d.T.string, default='docker.io/cryptpad/cryptpad:2026.5.1'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet' },
      },
    },
    paisa: {
      summary: 'A Paisa server (a plain-text, double-entry personal finance manager built on ledger/beancount journals). A plain composable http workload that reads its configuration and journal from a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI on :7500.',
      stages: {
        server: d.fn('The Paisa server, run from /data on the volume where it finds paisa.yaml and the referenced journal (provide them before first use). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='paisa'),
          d.arg('image', d.T.string, default='ghcr.io/ananthakumaran/paisa:0.7.4'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/paisa/server.libsonnet' },
      },
    },
    kanboard: {
      summary: 'A Kanboard server (a minimalist kanban project-management board) on the official image. A plain composable http workload that keeps board data in SQLite and uploads on a PersistentVolume — no external database by default. The nginx + PHP-FPM image starts as root and binds :80, so it relaxes non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Kanboard server. Keeps board data and uploads at /var/www/app/data on the volume. Point DATABASE_URL (env) at external PostgreSQL to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='kanboard'),
          d.arg('image', d.T.string, default='docker.io/kanboard/kanboard:v1.2.52'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/kanboard/server.libsonnet' },
      },
    },
    znc: {
      summary: 'A ZNC server (an IRC bouncer that stays connected and replays what you missed) on the official image. A plain composable http workload that keeps its configuration, module data, and buffers on a PersistentVolume. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves IRC and the web admin on :6697; needs a znc.conf (with credentials) on the volume before it starts.',
      stages: {
        server: d.fn('The ZNC server. Keeps everything at /znc-data on the volume. Provide a znc.conf at /znc-data/configs/znc.conf (generate with `znc --makeconf` or mount from a Secret — it holds passwords). Route the port as TCP.', [
          d.arg('name', d.T.string, default='znc'),
          d.arg('image', d.T.string, default='docker.io/library/znc:1.10.2'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/znc/server.libsonnet' },
      },
    },
    radicale: {
      summary: 'A Radicale server (a lightweight CalDAV and CardDAV server for calendars and contacts) on the tomsquest image. A plain composable http workload that keeps its collections on a PersistentVolume — no external database. The image runs as its designated uid 2999 with a writable root filesystem (s6 init). Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :5232; mount a config + htpasswd for real authentication.',
      stages: {
        server: d.fn('The Radicale server. Keeps collections at /data on the volume. Default config allows anonymous access — mount a Radicale config and htpasswd (kurly.config / kurly.secretMount) for htpasswd auth. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='radicale'),
          d.arg('image', d.T.string, default='docker.io/tomsquest/docker-radicale:3.7.6.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/radicale/server.libsonnet' },
      },
    },
    expenseowl: {
      summary: 'An ExpenseOwl server (a simple, self-hosted expense tracker). A plain composable http workload that keeps its expenses in a file-backed store on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :8080.',
      stages: {
        server: d.fn('The ExpenseOwl server. Keeps its expenses at /app/data on the volume, so it needs nothing external. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='expenseowl'),
          d.arg('image', d.T.string, default='ghcr.io/tanq16/expenseowl:v4.1'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/expenseowl/server.libsonnet' },
      },
    },
    homebox: {
      summary: 'A Homebox server (a simple home/household inventory and asset manager). A plain composable http workload on the rootless image that keeps its inventory in SQLite and attachments on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :7745.',
      stages: {
        server: d.fn('The Homebox server. Keeps inventory and attachments at /data on the volume (HBOX_STORAGE_*), so it needs nothing external. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='homebox'),
          d.arg('image', d.T.string, default='ghcr.io/sysadminsmedia/homebox:0.26.2-rootless'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/homebox/server.libsonnet' },
      },
    },
    actualbudget: {
      summary: 'An Actual Budget server (a local-first personal finance and budgeting app). A plain composable http workload that keeps its budgets and sync state in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web app and sync API on :5006.',
      stages: {
        server: d.fn('The Actual Budget server. Keeps everything in SQLite at /data on the volume (ACTUAL_DATA_DIR), so it needs nothing external. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='actualbudget'),
          d.arg('image', d.T.string, default='docker.io/actualbudget/actual-server:26.7.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet' },
      },
    },
    'uptime-kuma': {
      summary: 'An Uptime Kuma monitoring server (self-hosted uptime monitoring and status pages). A plain composable http workload that keeps its checks, history, and settings in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the dashboard and status pages on :3001.',
      stages: {
        server: d.fn('The Uptime Kuma server. Keeps everything in SQLite at /app/data on the volume, so it needs nothing external. env carries extra settings (UPTIME_KUMA_* overrides). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='uptime-kuma'),
          d.arg('image', d.T.string, default='docker.io/louislam/uptime-kuma:1.23.16'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/uptime-kuma/server.libsonnet' },
      },
    },
    netbox: {
      summary: 'A NetBox server (the IPAM/DCIM source of truth: IP address management, data-center infrastructure modelling, and a full REST/GraphQL API). Two composable stages on the community image — server (the web front end) and worker (the RQ background task worker) — with PostgreSQL and Redis external. Pairs with the cnpg-cluster and valkey workloads. Single writer over a ReadWriteOnce media volume: the server is one replica, recreated; the worker scales horizontally.',
      stages: {
        server: d.fn('The NetBox web front end, serving the UI and API on :8080. dbHost/dbName/dbUser default to a cnpg-cluster named netbox-db; redisHost to a valkey named netbox-cache (queue on Redis DB 0, cache on DB 1). secretName is the Secret the image reads at /run/secrets — secret_key (Django SECRET_KEY, keep it stable), db_password, and superuser_password on first boot. allowedHosts is Django ALLOWED_HOSTS. kurly authors no Secret. Compose an exposure onto the HTTP port; run a worker alongside.', [
          d.arg('name', d.T.string, default='netbox'),
          d.arg('image', d.T.string, default='docker.io/netboxcommunity/netbox:v4.6.5'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='netbox-db-rw'),
          d.arg('dbName', d.T.string, default='netbox'),
          d.arg('dbUser', d.T.string, default='netbox'),
          d.arg('redisHost', d.T.string, default='netbox-cache'),
          d.arg('secretName', d.T.string, default='netbox-secrets'),
          d.arg('allowedHosts', d.T.string, default='*'),
          d.arg('superuserName', d.T.string, default='admin'),
          d.arg('superuserEmail', d.T.string, default='admin@example.com'),
          d.arg('skipSuperuser', d.T.bool, default=false),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '300m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/netbox/server.libsonnet',
        },
        worker: d.fn('The NetBox RQ background worker, draining the high/default/low queues (webhooks, report/script runs, housekeeping). Same image and Secret as the server, no Service. dbHost/dbName/dbUser/redisHost/secretName match the server. Scales horizontally via replicas — workers coordinate through the shared Redis queue. A NetBox deployment needs at least one.', [
          d.arg('name', d.T.string, default='netbox-worker'),
          d.arg('image', d.T.string, default='docker.io/netboxcommunity/netbox:v4.6.5'),
          d.arg('dbHost', d.T.string, default='netbox-db-rw'),
          d.arg('dbName', d.T.string, default='netbox'),
          d.arg('dbUser', d.T.string, default='netbox'),
          d.arg('redisHost', d.T.string, default='netbox-cache'),
          d.arg('secretName', d.T.string, default='netbox-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'worker',
          importPath: 'github.com/metio/kurly/workloads/netbox/worker.libsonnet',
        },
      },
    },
    mailu: {
      summary: 'A Mailu mail server (SMTP, IMAP/POP3, webmail, antispam) as six coordinated http stages — front (the edge), admin (config + API + DB + DKIM), imap (Dovecot), smtp (Postfix), antispam (Rspamd), and webmail (Roundcube). Run all six pointed at the same namePrefix, secretName, and a shared ReadWriteMany storageClaim, plus a Redis (the valkey workload). Mailu images run as root with a writable root filesystem, so these relax kurly restricted defaults while keeping dropped capabilities and no privilege escalation. Each service is one replica, recreated; expose only front.',
      stages: {
        front: d.fn('The Mailu edge (nginx): terminates SMTP/IMAP/POP3/ManageSieve and the web UI and proxies to the other services. The one stage you expose. domain/hostnames identify the mail server; secretName carries SECRET_KEY (envFrom, kurly mints none); storageClaim is the shared RWM volume; redisAddress points at a valkey. Publishes 25/465/587/110/995/143/993/4190/80/443.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/nginx:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resolverAddress', d.T.string, default=''),
          d.arg('tlsFlavor', d.T.string, default='mail'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/front.libsonnet' },
        admin: d.fn('The Mailu administration service: web admin UI, the internal API the other services query, and the SQLite database and DKIM keys behind them (on the shared volume at /data and /dkim). front proxies /admin to it.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/admin:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resolverAddress', d.T.string, default=''),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/admin.libsonnet' },
        imap: d.fn('The Mailu mail store (Dovecot): holds the maildirs at /mail on the shared volume and serves IMAP/POP3 to front and LMTP delivery to postfix.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/dovecot:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resolverAddress', d.T.string, default=''),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/imap.libsonnet' },
        smtp: d.fn('The Mailu MTA (Postfix): relays mail between the edge, the filter, and the store. The queue is transient; only user overrides live on the shared volume.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/postfix:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resolverAddress', d.T.string, default=''),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/smtp.libsonnet' },
        antispam: d.fn('The Mailu filter (Rspamd): screens mail on :11332, serves its web UI on :11334, and signs outbound mail with the DKIM keys admin generates. Learned state lives at /var/lib/rspamd on the shared volume.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/rspamd:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resolverAddress', d.T.string, default=''),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/antispam.libsonnet' },
        webmail: d.fn('The Mailu webmail client (Roundcube): front proxies /webmail to it. Optional — drop it if you only want IMAP/SMTP clients. Keeps its settings at /data on the shared volume.', [
          d.arg('namePrefix', d.T.string, default='mailu'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='ghcr.io/mailu/webmail:2024.06'),
          d.arg('domain', d.T.string, default='example.com'),
          d.arg('hostnames', d.T.array, default=['mail.example.com']),
          d.arg('secretName', d.T.string, default='mailu-secrets'),
          d.arg('storageClaim', d.T.string, default='mailu-storage'),
          d.arg('subnet', d.T.string, default='10.0.0.0/8'),
          d.arg('redisAddress', d.T.string, default='mailu-cache'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mailu/webmail.libsonnet' },
      },
    },
    forgejo: {
      summary: 'A Forgejo Git forge (a maintained Gitea fork): repository hosting, issues, pull requests, and a package registry. A plain composable http workload on the rootless image, with its data on a PersistentVolume and its database external — pairs with the cnpg-cluster workload. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI/git-over-HTTP on :3000 and git-over-SSH on :2222.',
      stages: {
        server: d.fn('The Forgejo server. dbHost/dbName/dbUser/dbSecret default to a cnpg-cluster named forgejo-db (its -rw Service and the -app Secret CNPG mints, key password read via a file). rootUrl is the public base URL for links/clone URLs. env carries extra FORGEJO__section__KEY settings — provide SECRET_KEY/JWT_SECRET there (from a Secret) so sessions survive restarts. kurly authors no Secret. Compose an exposure onto the HTTP port; route TCP :2222 for SSH.', [
          d.arg('name', d.T.string, default='forgejo'),
          d.arg('image', d.T.string, default='codeberg.org/forgejo/forgejo:16.0-rootless'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='forgejo-db-rw'),
          d.arg('dbName', d.T.string, default='forgejo'),
          d.arg('dbUser', d.T.string, default='forgejo'),
          d.arg('dbSecret', d.T.string, default='forgejo-db-app'),
          d.arg('rootUrl', d.T.string, example='https://git.example.com/'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/forgejo/server.libsonnet',
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
          d.arg('storageClass', d.T.string),
          d.arg('walSize', d.T.quantity, example='5Gi'),
          d.arg('walStorageClass', d.T.string, example='fast-nvme'),
          d.arg('imageName', d.T.string),
          d.arg('catalog', d.T.string, example='postgres'),
          d.arg('catalogScope', d.T.string, default='namespaced'),
          d.arg('major', d.T.int, example=17),
          d.arg('database', d.T.string, default='app'),
          d.arg('owner', d.T.string, default='app'),
          d.arg('parameters', d.T.object, default={}, example={ huge_pages: 'on', shared_buffers: '1800MB' }),
          d.arg('resources', d.T.object),
          d.arg('enablePodMonitor', d.T.bool, default=true),
          d.arg('imagePullSecrets', d.T.array, default=[]),
          d.arg('serviceAccountAnnotations', d.T.object, default={}, example={ 'eks.amazonaws.com/role-arn': 'arn:aws:iam::123456789012:role/pg-backup' }),
          d.arg('labels', d.T.object, default={}, example={ team: 'payments' }),
          d.arg('annotations', d.T.object, default={}),
          d.arg('affinity', d.T.object, example={ nodeSelector: { workload: 'database' }, podAntiAffinityType: 'required' }),
          d.arg('topologySpreadConstraints', d.T.array, default=[]),
          d.arg('priorityClassName', d.T.string),
          d.arg('schedulerName', d.T.string),
          d.arg('backup', d.T.object, example={ barmanObjectStore: { destinationPath: 's3://backups/', endpointURL: 'http://seaweedfs:8333' } }),
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
          d.arg('componentImages', d.T.object, default={}),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'cnpg',
          importPath: 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet',
        },
        cluster: d.fn('A cluster-scoped ClusterImageCatalog, serving every namespace from one object. Identical spec to the namespaced stage; a cnpg-cluster points at it with catalogScope=cluster.', [
          d.arg('name', d.T.string, default='postgres'),
          d.arg('images', d.T.object, default={ '17': 'ghcr.io/cloudnative-pg/postgresql:17.2' }),
          d.arg('componentImages', d.T.object, default={}),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
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
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('maxMemoryMB', d.T.int, default=512),
          d.arg('threads', d.T.int, default=2),
          d.arg('snapshotCron', d.T.string, example='0 */6 * * *'),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet',
        },
      },
    },
    'otel-collector': {
      summary: "An OpenTelemetry Collector as a per-node agent (a DaemonSet), so local workloads send telemetry to a collector on their own node. The collector config — receivers, processors, exporters, and the pipelines wiring them — is passed verbatim (it is the collector's schema, not kurly's); the default is a working OTLP agent that receives, batches, and prints. Fully restricted by default: node-log collection needs a hostPath and is a documented opt-in.",
      stages: {
        agent: d.fn("The per-node collector. config is the collector's own document, rendered straight into the mounted config file; the default receives OTLP on 4317/4318, guards memory, batches, and exports to the debug logger, with a health_check extension on 13133 backing the probes. Replace config for real pipelines, and move the probes if it drops health_check.", [
          d.arg('name', d.T.string, default='otel-collector'),
          d.arg('image', d.T.string, default='docker.io/otel/opentelemetry-collector-contrib:0.156.0'),
          d.arg('config', d.T.object, example={ receivers: {}, exporters: {}, service: { pipelines: {} } }),
        ]) + {
          kind: 'daemon',
          importPath: 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet',
        },
      },
    },
    'blackbox-exporter': {
      summary: 'The Prometheus blackbox_exporter: it probes endpoints from the outside (HTTP, TCP, DNS, ICMP) and turns each probe into metrics. A plain composable http workload, deployed once as the prober kurly.expose.probe points a workload Probe at. Serves /probe on :9115.',
      stages: {
        server: d.fn('The exporter. modules is rendered as its config.yml; the default covers http_2xx (dual-stack) plus IPv4/IPv6-pinned variants and tcp_connect. Reach it at blackbox-exporter:9115 (the kurly.expose.probe default prober). An ICMP module needs CAP_NET_RAW, so relax the dropped capabilities for it.', [
          d.arg('name', d.T.string, default='blackbox-exporter'),
          d.arg('image', d.T.string, default='quay.io/prometheus/blackbox-exporter:v0.28.0'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('modules', d.T.object),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '64Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet',
        },
      },
    },
    alertmanager: {
      summary: 'An Alertmanager as a prometheus-operator `Alertmanager` custom resource: it receives alerts from a Prometheus, groups and deduplicates them, and routes them to receivers. Authors the CR (like prometheus) for the operator to reconcile into a StatefulSet and the `alertmanager-operated` Service. Requires the prometheus-operator installed. Routing comes from the AlertmanagerConfig objects it selects.',
      stages: {
        server: d.fn("The Alertmanager. alertmanagerConfigSelector (verbatim operator schema) decides which AlertmanagerConfig objects supply routing/receivers; {} selects everything, none runs the operator default. Wire a Prometheus to it through that workload's spec escape (alerting.alertmanagers -> alertmanager-operated:web). Reach it at alertmanager-operated.<namespace>.svc:9093.", [
          d.arg('name', d.T.string, default='alertmanager'),
          d.arg('image', d.T.string, default='docker.io/prom/alertmanager:v0.33.1'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('retention', d.T.string, default='120h'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('alertmanagerConfigSelector', d.T.object, default={}),
          d.arg('namespaceSelector', d.T.object, default={}),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ externalUrl: 'https://alertmanager.example.com' }),
        ]) + {
          kind: 'alertmanager',
          importPath: 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet',
        },
      },
    },
    keycloak: {
      summary: 'A Keycloak identity server as an official keycloak-operator `Keycloak` custom resource. Authors the CR (like loki and tempo) for the operator to reconcile into a StatefulSet, Services, and the admin credentials Secret. Requires the keycloak-operator (whose recent releases let one operator manage instances across many namespaces) and a PostgreSQL database — pairs with the cnpg-cluster workload.',
      stages: {
        server: d.fn("The Keycloak server. It needs a PostgreSQL database: dbHost/dbName/dbSecret default to a cnpg-cluster named keycloak-db (its -rw Service and the -app Secret CNPG mints, keys username/password). hostname is the public URL for production; tlsSecret names the cert Keycloak terminates, or plain HTTP (httpEnabled) behind a TLS-terminating proxy. The operator chooses the Keycloak image unless image pins one. kurly authors no Secret — the database and TLS Secrets are the consumer's.", [
          d.arg('name', d.T.string, default='keycloak'),
          d.arg('instances', d.T.int, default=1),
          d.arg('image', d.T.string, example='quay.io/keycloak/keycloak:26.7.0'),
          d.arg('dbHost', d.T.string, default='keycloak-db-rw'),
          d.arg('dbName', d.T.string, default='keycloak'),
          d.arg('dbSecret', d.T.string, default='keycloak-db-app'),
          d.arg('hostname', d.T.hostname, example='https://id.example.com'),
          d.arg('tlsSecret', d.T.string, example='keycloak-tls'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ proxy: { headers: 'xforwarded' } }),
        ]) + {
          kind: 'keycloak',
          importPath: 'github.com/metio/kurly/workloads/keycloak/server.libsonnet',
        },
      },
    },
    thanos: {
      summary: 'The Thanos components as separate, independently-scaled stages under one workload: query (the stateless Querier fanning out to StoreAPIs for a deduplicated global view), query-frontend (an optional splitting/caching layer in front of it), and ruler (recording/alerting rules evaluated against Query). query and query-frontend are plain composable http workloads; ruler authors a prometheus-operator ThanosRuler custom resource and needs that operator installed.',
      stages: {
        query: d.fn('The Thanos Querier (a plain `thanos query` Deployment + Service). endpoints are the StoreAPI targets it fans out to over gRPC (dnssrv+ resolves every replica); queryReplicaLabels deduplicate HA replicas. Serves the Prometheus API on :10902 (gRPC StoreAPI on :10901 for federation). Point a Grafana datasource or the query-frontend at it.', [
          d.arg('name', d.T.string, default='thanos-query'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('endpoints', d.T.array, default=[], example=['dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local']),
          d.arg('queryReplicaLabels', d.T.array, default=['prometheus_replica', 'replica']),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('extraArgs', d.T.array, default=[]),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/thanos/query.libsonnet',
        },
        'query-frontend': d.fn('The Thanos Query Frontend (a plain `thanos query-frontend` Deployment + Service): an optional layer that splits long-range queries, caches results (in-memory by default), and forwards to a downstream Querier. downstreamUrl defaults to a thanos-query Service on :10902 in the same namespace. For a shared cache, pass --query-range.response-cache-config-file via extraArgs and back it with the memcached or valkey workload.', [
          d.arg('name', d.T.string, default='thanos-query-frontend'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('downstreamUrl', d.T.string, default='http://thanos-query:10902'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('extraArgs', d.T.array, default=[]),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet',
        },
        store: d.fn('The Thanos Store Gateway (a `thanos store` StatefulSet + headless Service): it serves historical blocks from object storage over the StoreAPI so the Querier reaches data older than the sidecars hold. Stateful — a per-pod PVC caches block index headers. objstoreSecret names a Secret you provide (key objstore.yaml, fillable with kurly.externalSecret) pointing at the bucket; it pairs with the seaweedfs S3 workload. Add it to the Querier with dnssrv+_grpc._tcp.<name>-headless…', [
          d.arg('name', d.T.string, default='thanos-store'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('objstoreSecret', d.T.string, default='thanos-objstore'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('extraArgs', d.T.array, default=[]),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/thanos/store.libsonnet',
        },
        compact: d.fn('The Thanos Compactor (a `thanos compact --wait` Deployment): it compacts raw blocks in object storage, builds the 5m/1h downsampled resolutions, and applies retention. A SINGLETON — a second compactor over the same bucket corrupts the data, so replicas is pinned to 1 (asserted) and it rolls with Recreate; shard a large bucket with --selector.relabel-config across separate compactors. Reads the same objstoreSecret as store. retentionRaw/5m/1h bound each resolution (0d = keep forever).', [
          d.arg('name', d.T.string, default='thanos-compact'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('objstoreSecret', d.T.string, default='thanos-objstore'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('retentionRaw', d.T.string, default='0d'),
          d.arg('retention5m', d.T.string, default='0d'),
          d.arg('retention1h', d.T.string, default='0d'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('extraArgs', d.T.array, default=[]),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/thanos/compact.libsonnet',
        },
        receive: d.fn('The Thanos Receiver (a `thanos receive` StatefulSet + headless Service): the push-based ingestion path — Prometheus remote-writes to it (:19291) instead of running a sidecar. It holds recent data in a local TSDB, serves it to the Querier over the StoreAPI (:10901), and uploads blocks to object storage. Receivers form a hashring generated from the replica count; replicationFactor copies each series across pods, each tagged with a receive_replica label the Querier deduplicates. Reads the same objstoreSecret as store.', [
          d.arg('name', d.T.string, default='thanos-receive'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('replicationFactor', d.T.int, default=1),
          d.arg('objstoreSecret', d.T.string, default='thanos-objstore'),
          d.arg('tsdbRetention', d.T.string, default='15d'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('extraArgs', d.T.array, default=[]),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/thanos/receive.libsonnet',
        },
        ruler: d.fn('The Thanos Ruler as a prometheus-operator ThanosRuler custom resource. queryEndpoints (verbatim operator schema, dnssrv+ resolves every Query replica) are what it evaluates rules against; ruleSelector/ruleNamespaceSelector decide which PrometheusRule objects it loads ({} selects everything, none selects nothing). alertmanagersUrl lists plain Alertmanager targets; for authenticated ones reference your own Secret through spec.alertmanagersConfig. Reach it at thanos-ruler-operated.<namespace>.svc:10902.', [
          d.arg('name', d.T.string, default='thanos-ruler'),
          d.arg('image', d.T.string, default='quay.io/thanos/thanos:v0.42.2'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('queryEndpoints', d.T.array, default=[], example=['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local']),
          d.arg('alertmanagersUrl', d.T.array, default=[], example=['http://alertmanager-operated.monitoring.svc:9093']),
          d.arg('ruleSelector', d.T.object, default={}),
          d.arg('ruleNamespaceSelector', d.T.object, default={}),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ alertQueryUrl: 'https://thanos-ruler.example.com' }),
        ]) + {
          kind: 'thanos-ruler',
          importPath: 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet',
        },
      },
    },
    grafana: {
      summary: 'A Grafana instance as a grafana-operator `Grafana` custom resource, with a Prometheus `GrafanaDatasource` wired in by default — the o11y pairing with the prometheus workload. Authors the CRs (like cnpg-cluster) for the operator to reconcile into a Deployment, Service, and ServiceAccount. Requires the grafana-operator installed.',
      stages: {
        server: d.fn("The Grafana instance. config is grafana.ini (operator sections of string values), merged over defaults that silence phone-home traffic. prometheusUrl points the default datasource at the prometheus workload's prometheus-operated Service; prometheusDatasource=false authors none. The operator mints a random admin password into <name>-admin-credentials.", [
          d.arg('name', d.T.string, default='grafana'),
          d.arg('image', d.T.string, default='docker.io/grafana/grafana:13.1.0'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('config', d.T.object, default={}, example={ server: { root_url: 'https://grafana.example.com' } }),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('prometheusDatasource', d.T.bool, default=true),
          d.arg('prometheusUrl', d.T.string, default='http://prometheus-operated:9090'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ ingress: { spec: {} } }),
        ]) + {
          kind: 'grafana',
          importPath: 'github.com/metio/kurly/workloads/grafana/server.libsonnet',
        },
      },
    },
    loki: {
      summary: 'Grafana Loki in microservices mode as a loki-operator `LokiStack` custom resource: one CR reconciles the whole distributed topology (distributor, ingester, querier, query-frontend, compactor, index-gateway, gateway), with `size` scaling the replicas. Authors the CR (like cnpg-cluster) for the operator to own the components, config, and ring. Requires the loki-operator and an object-storage Secret. Pairs with the seaweedfs workload for S3.',
      stages: {
        server: d.fn("The LokiStack. size is the operator's t-shirt scaling (1x.demo is the smallest, for a test cluster; production wants 1x.extra-small+). storageSecret names the object-storage Secret you create (keys bucketnames/endpoint/access_key_id/access_key_secret/region) — point it at the seaweedfs workload's S3. The operator chooses the Loki image, so there is none to pin. Reach it at the gateway Service lokistack-gateway-http.", [
          d.arg('name', d.T.string, default='loki'),
          d.arg('size', d.T.string, default='1x.demo'),
          d.arg('storageSecret', d.T.string, default='loki-storage'),
          d.arg('storageClass', d.T.string),
          d.arg('schemaVersion', d.T.string, default='v13'),
          d.arg('schemaEffectiveDate', d.T.string, default='2024-01-01'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ tenants: { mode: 'static' } }),
        ]) + {
          kind: 'loki',
          importPath: 'github.com/metio/kurly/workloads/loki/server.libsonnet',
        },
      },
    },
    tempo: {
      summary: 'Grafana Tempo as a tempo-operator `TempoStack` custom resource: one CR reconciles the whole distributed tracing backend (distributor, ingester, querier, query-frontend, compactor) over object storage. Authors the CR (the same shape as loki) for the operator to own the components, config, and Services. Requires the tempo-operator and an object-storage Secret. Pairs with the seaweedfs workload for S3 and the otel-collector workload for span ingestion.',
      stages: {
        server: d.fn("The TempoStack. storageSecret names the object-storage Secret you create (keys bucket/endpoint/access_key_id/access_key_secret) — point it at the seaweedfs workload's S3. storageSize is the per-component PVC. The operator chooses the Tempo image, so there is none to pin. Send spans to tempo-<name>-distributor (OTLP :4317/:4318) and read them from Grafana via tempo-<name>-query-frontend:3200.", [
          d.arg('name', d.T.string, default='tempo'),
          d.arg('storageSecret', d.T.string, default='tempo-storage'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ replicationFactor: 2 }),
        ]) + {
          kind: 'tempo',
          importPath: 'github.com/metio/kurly/workloads/tempo/server.libsonnet',
        },
      },
    },
    prometheus: {
      summary: 'A Prometheus server as a prometheus-operator `Prometheus` custom resource, with the cluster-scoped RBAC it scrapes with. Authors the CR (like cnpg-cluster) for the operator to reconcile into a StatefulSet and the `prometheus-operated` Service. Requires the prometheus-operator installed. The default is central monitoring: it selects every ServiceMonitor/PodMonitor in every namespace.',
      stages: {
        server: d.fn('The Prometheus server. namespace MUST match where you deploy — it names the ServiceAccount in the cluster RoleBinding, which a cluster-scoped object cannot inherit later. The selectors (verbatim operator schema) default to selecting everything; scope them to narrow what it scrapes. Query it at prometheus-operated.<namespace>.svc:9090.', [
          d.arg('name', d.T.string, default='prometheus'),
          d.arg('namespace', d.T.string, default='monitoring'),
          d.arg('image', d.T.string, default='docker.io/prom/prometheus:v3.13.1'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('retention', d.T.string, default='15d'),
          d.arg('storageSize', d.T.quantity, default='50Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('scrapeInterval', d.T.string, default='30s'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '2Gi' } }),
          d.arg('externalLabels', d.T.object, default={}, example={ cluster: 'prod' }),
          d.arg('serviceMonitorSelector', d.T.object, default={}),
          d.arg('podMonitorSelector', d.T.object, default={}),
          d.arg('ruleSelector', d.T.object, default={}),
          d.arg('probeSelector', d.T.object, default={}),
          d.arg('namespaceSelector', d.T.object, default={}),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
          d.arg('spec', d.T.object, default={}, example={ enableRemoteWriteReceiver: true }),
        ]) + {
          kind: 'prometheus',
          importPath: 'github.com/metio/kurly/workloads/prometheus/server.libsonnet',
        },
      },
    },
    'metrics-server': {
      summary: "The Kubernetes Metrics Server: it scrapes CPU/memory usage from every node's kubelet and serves it through the aggregated metrics.k8s.io API — what kubectl top and Horizontal Pod Autoscalers read. A plain composable http workload that registers an APIService and carries the aggregation RBAC (ServiceAccount, ClusterRoles/Bindings, the kube-system auth-reader RoleBinding).",
      stages: {
        server: d.fn('The metrics server. namespace MUST match where you deploy — the APIService and cluster RBAC name the ServiceAccount by namespace, which cluster-scoped objects cannot inherit later; kube-system is conventional. kubeletInsecureTLS=true skips verifying the kubelet serving cert (needed on kind and many on-prem clusters, or every scrape fails the TLS handshake).', [
          d.arg('name', d.T.string, default='metrics-server'),
          d.arg('namespace', d.T.string, default='kube-system'),
          d.arg('image', d.T.string, default='registry.k8s.io/metrics-server/metrics-server:v0.8.1'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('kubeletInsecureTLS', d.T.bool, default=false),
          d.arg('metricResolution', d.T.string, default='15s'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '200Mi' }, limits: { memory: '400Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet',
        },
      },
    },
    opencost: {
      summary: 'OpenCost, the CNCF cost-monitoring model: it reads resource usage from Prometheus, joins it with pricing, and exposes per-workload cost metrics (and an API) on :9003. A plain composable http workload that carries a ServiceAccount + ClusterRole + ClusterRoleBinding, because attributing cost reads cluster-scoped objects and every namespace. Pairs with the prometheus (or thanos) workload as its data source.',
      stages: {
        server: d.fn('The OpenCost cost model. namespace MUST match where you deploy — it names the ServiceAccount in the cluster RoleBinding, which a cluster-scoped object cannot inherit later. prometheusEndpoint points at the prometheus workload (or a Thanos Query); env carries extra pricing/cloud settings. The web UI is a separate image (opencost-ui); this is the model, scraped at :9003.', [
          d.arg('name', d.T.string, default='opencost'),
          d.arg('namespace', d.T.string, default='opencost'),
          d.arg('image', d.T.string, default='ghcr.io/opencost/opencost:1.119.2'),
          d.arg('prometheusEndpoint', d.T.string, default='http://prometheus-operated.monitoring.svc:9090'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'http',
          importPath: 'github.com/metio/kurly/workloads/opencost/server.libsonnet',
        },
      },
    },
    seaweedfs: {
      summary: "SeaweedFS as an all-in-one object store: a StatefulSet with a per-pod PVC and a headless Service running `weed server -s3`, so one process is master, volume, filer, and an S3 gateway. It gives a cluster an S3 API on 8333 backed by a PersistentVolume — an in-cluster target for anything that speaks S3, such as a cnpg-cluster's backups.",
      stages: {
        server: d.fn('The all-in-one server. Serves S3 on 8333 over the data volume at /data; the master/volume/filer ports serve the cluster itself. The default allows anonymous access, fine inside a trusted namespace. Splitting the roles into dedicated tiers is a different topology, not more replicas, so it would be its own stage.', [
          d.arg('name', d.T.string, default='seaweedfs'),
          d.arg('image', d.T.string, default='docker.io/chrislusf/seaweedfs:4.39'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet',
        },
        master: d.fn("The coordinator of a SPLIT SeaweedFS: `weed master` holds the topology, assigns file IDs, and directs clients to volume servers. defaultReplication is the cluster-wide policy it owns ('000' keeps one copy). Deploy it, then point the volume and filer stages at it.", [
          d.arg('name', d.T.string, default='seaweedfs-master'),
          d.arg('image', d.T.string, default='docker.io/chrislusf/seaweedfs:4.39'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('defaultReplication', d.T.string, default='000'),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet',
        },
        volume: d.fn('The data tier of a SPLIT SeaweedFS: `weed volume` stores file content and registers with the master, advertising its pod IP so reads reach it. Scale by replicas for capacity, each a pod with its own PVC. Point it at the master with masterEndpoint.', [
          d.arg('name', d.T.string, default='seaweedfs-volume'),
          d.arg('image', d.T.string, default='docker.io/chrislusf/seaweedfs:4.39'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('masterEndpoint', d.T.string, default='seaweedfs-master-0.seaweedfs-master-headless:9333'),
          d.arg('maxVolumes', d.T.int, default=100),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet',
        },
        filer: d.fn('The access tier of a SPLIT SeaweedFS: `weed filer` puts a filesystem and (s3=true) an S3 gateway on 8333 over the volume servers, keeping its own metadata. Point it at the master with masterEndpoint.', [
          d.arg('name', d.T.string, default='seaweedfs-filer'),
          d.arg('image', d.T.string, default='docker.io/chrislusf/seaweedfs:4.39'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('masterEndpoint', d.T.string, default='seaweedfs-master-0.seaweedfs-master-headless:9333'),
          d.arg('s3', d.T.bool, default=true),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet',
        },
      },
    },
    memcached: {
      summary: "An in-memory cache sharded by the client, as a StatefulSet whose storage is nothing and whose identity is everything. No replication and no persistence: an upgrade always starts cold, and stable pod names are what bound the loss to 1/N of a client's keyspace.",
      stages: {
        cache: d.fn('The memcached shards: a StatefulSet (for stable DNS names, not storage) and the headless Service that names them. Clients consistent-hash keys over memcached-0..N-1; scaling reshuffles that ring, so treat replicas as part of the client configuration. The container memory limit is derived from memoryMB, since -m caps only the item cache.', [
          d.arg('name', d.T.string, default='memcached'),
          d.arg('image', d.T.string, default='docker.io/library/memcached:1.6.45'),
          d.arg('replicas', d.T.int, default=3),
          d.arg('memoryMB', d.T.int, default=64),
          d.arg('maxConnections', d.T.int, default=1024),
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
          d.arg('image', d.T.string, default='docker.io/valkey/valkey:9.1.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('maxMemory', d.T.string, example='512mb'),
        ]) + {
          kind: 'stateful',
          importPath: 'github.com/metio/kurly/workloads/valkey/instance.libsonnet',
        },
        cache: d.fn('An in-memory Valkey cache that upgrades its version with zero downtime and no data loss, on the stock image and no orchestrator — the replication hand-off lives entirely in the pod manifests (headless Service, maxSurge, an initContainer that replicates the running peer, and a preStop failover).', [
          d.arg('name', d.T.string, default='valkey'),
          d.arg('image', d.T.string, default='docker.io/valkey/valkey:9.1.0'),
          d.arg('maxMemory', d.T.string, default='256mb'),
          d.arg('kubectlImage', d.T.string, default='docker.io/alpine/k8s:1.36.2'),
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
    externalSecret: d.fn("Authors an External Secrets Operator ExternalSecret — the CR ESO reconciles into a Kubernetes Secret by pulling values from an external store (Vault, AWS/GCP Secrets Manager). kurly never mints key material (a policy invariant), so any named Secret a workload references can be filled by ESO instead of applied by hand. The target Secret takes the ExternalSecret's own name, matching the name the workload parameter points at. secretStoreRef and the data entries pass through verbatim — kurly does not model ESO's remoteRef schema, which would drift against its API.", [
      d.arg('name', d.T.string, required=true, example='loki-storage'),
      d.arg('secretStoreRef', d.T.object, required=true),
      d.arg('data', d.T.array, required=true),
      d.arg('refreshInterval', d.T.string, default='1h'),
    ]),
    certificate: d.fn("Authors a cert-manager Certificate — the CR cert-manager reconciles into a TLS Secret by obtaining a certificate for the DNS names from an issuer. The mint end of the same seam as externalSecret: a workload names the tls Secret it terminates on (an exposure's tls, keycloak's tlsSecret) and authors none, so this fills it with a real, auto-renewed certificate. secretName defaults to the Certificate's own name, so a workload's tls parameter pointed at that name lines up. issuerRef defaults to a ClusterIssuer.", [
      d.arg('name', d.T.string, required=true, example='storefront-tls'),
      d.arg('dnsNames', d.T.array, required=true, example=['storefront.example.com']),
      d.arg('issuer', d.T.string, required=true, example='letsencrypt-prod'),
      d.arg('secretName', d.T.string),
      d.arg('issuerKind', d.T.string, default='ClusterIssuer'),
      d.arg('duration', d.T.string),
      d.arg('renewBefore', d.T.string),
    ]),
  },
}
