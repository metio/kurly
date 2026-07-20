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
    wordpress: {
      summary: 'A WordPress server (the popular CMS and blogging platform) on the official image, backed by an external MySQL/MariaDB, with content (themes, plugins, uploads) on a PersistentVolume. kurly ships no MySQL recipe — bring your own. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; WORDPRESS_DB_PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The WordPress server. dbHost/dbName/dbUser point at a MySQL/MariaDB you provide. secretName holds WORDPRESS_DB_PASSWORD (envFrom). Content at /var/www/html. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='wordpress'),
          d.arg('image', d.T.string, default='docker.io/library/wordpress:6.9.4-php8.3-apache'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='wordpress-db'),
          d.arg('dbName', d.T.string, default='wordpress'),
          d.arg('dbUser', d.T.string, default='wordpress'),
          d.arg('secretName', d.T.string, default='wordpress-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/wordpress/server.libsonnet' },
      },
    },
    etherpad: {
      summary: 'An Etherpad server (a real-time collaborative document editor) on the official image, backed by an external PostgreSQL. Its documents live in the database, so it is stateless and can run several replicas. Pairs with a cnpg-cluster named etherpad-db. kurly authors no Secret; DB_PASS, ADMIN_PASSWORD, and APIKEY come from a provided Secret via envFrom. Serves on :9001.',
      stages: {
        server: d.fn('The Etherpad server. dbHost/dbName/dbUser default to a cnpg-cluster named etherpad-db. secretName holds DB_PASS, ADMIN_PASSWORD, and APIKEY (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='etherpad'),
          d.arg('image', d.T.string, default='docker.io/etherpad/etherpad:3.3.2'),
          d.arg('dbHost', d.T.string, default='etherpad-db-rw'),
          d.arg('dbName', d.T.string, default='etherpad'),
          d.arg('dbUser', d.T.string, default='etherpad'),
          d.arg('secretName', d.T.string, default='etherpad-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/etherpad/server.libsonnet' },
      },
    },
    hedgedoc: {
      summary: 'A HedgeDoc server (real-time, collaborative markdown notes) on the official image, backed by an external PostgreSQL, with uploaded files on a PersistentVolume. Pairs with a cnpg-cluster named hedgedoc-db. kurly authors no Secret; CMD_DB_URL and CMD_SESSION_SECRET come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The HedgeDoc server. domain is the public domain. secretName holds CMD_DB_URL (with the DB password) and CMD_SESSION_SECRET (envFrom). Uploads at /hedgedoc/public/uploads. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='hedgedoc'),
          d.arg('image', d.T.string, default='quay.io/hedgedoc/hedgedoc:1.11.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('domain', d.T.string, example='pad.example.com'),
          d.arg('secretName', d.T.string, default='hedgedoc-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet' },
      },
    },
    dex: {
      summary: 'A Dex server (an OpenID Connect / OAuth 2.0 identity provider that federates to upstream connectors — LDAP, SAML, GitHub, Google, …) on the official image. A plain composable http workload; with the SQLite storage backend its state lives on a PersistentVolume, no external database. Driven entirely by a config.yaml (issuer, storage, connectors, staticClients) mounted from a Secret — kurly authors none. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves OIDC on :5556.',
      stages: {
        server: d.fn('The Dex server (runs `dex serve /etc/dex/config.yaml`). SQLite state at /var/dex on the volume. configSecret is the Secret holding config.yaml (mounted at /etc/dex; it carries client and connector secrets). Point storage at PostgreSQL in the config, or the kubernetes backend with kurly.rbac, to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='dex'),
          d.arg('image', d.T.string, default='ghcr.io/dexidp/dex:v2.45.1'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('configSecret', d.T.string, default='dex-config'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/dex/server.libsonnet' },
      },
    },
    vikunja: {
      summary: 'A Vikunja server (a self-hosted to-do and project-management app) on the official all-in-one image. A plain composable http workload that keeps its data in SQLite and file attachments on a PersistentVolume by default — no external database. kurly authors no Secret; VIKUNJA_SERVICE_JWTSECRET comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3456.',
      stages: {
        server: d.fn('The Vikunja server. Database at /db, attachments at /files, both on the volume. publicUrl is the public URL; secretName holds VIKUNJA_SERVICE_JWTSECRET (envFrom, keep it stable). Point VIKUNJA_DATABASE_TYPE at external Postgres/MySQL via env to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='vikunja'),
          d.arg('image', d.T.string, default='docker.io/vikunja/vikunja:v2.4.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('publicUrl', d.T.string, example='https://tasks.example.com'),
          d.arg('secretName', d.T.string, default='vikunja-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/vikunja/server.libsonnet' },
      },
    },
    listmonk: {
      summary: 'A listmonk server (a self-hosted newsletter and mailing-list manager) on the official image, backed by an external PostgreSQL, with uploaded media on a PersistentVolume. Pairs with a cnpg-cluster named listmonk-db. kurly authors no Secret; the DB and admin passwords come from a provided Secret via envFrom. Run the one-time schema install before first use. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :9000.',
      stages: {
        server: d.fn('The listmonk server. dbHost/dbName/dbUser default to a cnpg-cluster named listmonk-db; adminUser is the admin. secretName holds LISTMONK_db__password and LISTMONK_app__admin_password (envFrom). Uploads at /listmonk/uploads. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='listmonk'),
          d.arg('image', d.T.string, default='docker.io/listmonk/listmonk:v6.2.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='listmonk-db-rw'),
          d.arg('dbName', d.T.string, default='listmonk'),
          d.arg('dbUser', d.T.string, default='listmonk'),
          d.arg('adminUser', d.T.string, default='admin'),
          d.arg('secretName', d.T.string, default='listmonk-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/listmonk/server.libsonnet' },
      },
    },
    umami: {
      summary: 'An Umami server (a simple, privacy-focused, self-hosted web-analytics alternative to Google Analytics) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. kurly authors no Secret; DATABASE_URL and APP_SECRET come from a provided Secret via envFrom. Pairs with a cnpg-cluster named umami-db. Serves on :3000.',
      stages: {
        server: d.fn('The Umami server. secretName holds DATABASE_URL (with the DB password) and APP_SECRET (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='umami'),
          d.arg('image', d.T.string, default='ghcr.io/umami-software/umami:postgresql-v2.15.1'),
          d.arg('secretName', d.T.string, default='umami-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/umami/server.libsonnet' },
      },
    },
    linkwarden: {
      summary: 'A Linkwarden server (a self-hosted bookmark manager that archives a copy of every page) on the official image, backed by an external PostgreSQL, with archived pages on a PersistentVolume. Pairs with a cnpg-cluster named linkwarden-db. kurly authors no Secret; DATABASE_URL and NEXTAUTH_SECRET come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The Linkwarden server. nextauthUrl is the public URL. secretName holds DATABASE_URL (with the DB password) and NEXTAUTH_SECRET (envFrom). Archived pages at /data/data on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='linkwarden'),
          d.arg('image', d.T.string, default='ghcr.io/linkwarden/linkwarden:v2.15.1'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('nextauthUrl', d.T.string, example='https://links.example.com'),
          d.arg('secretName', d.T.string, default='linkwarden-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet' },
      },
    },
    miniflux: {
      summary: 'A Miniflux server (a minimalist, opinionated RSS/Atom feed reader) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. kurly authors no Secret; DATABASE_URL and the admin password come from a provided Secret via envFrom. Pairs with a cnpg-cluster named miniflux-db. Serves on :8080.',
      stages: {
        server: d.fn('The Miniflux server. secretName holds DATABASE_URL (with the DB password) and ADMIN_PASSWORD (envFrom); adminUser is the first-run admin. Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='miniflux'),
          d.arg('image', d.T.string, default='docker.io/miniflux/miniflux:2.3.2'),
          d.arg('secretName', d.T.string, default='miniflux-secrets'),
          d.arg('adminUser', d.T.string, default='admin'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/miniflux/server.libsonnet' },
      },
    },
    freshrss: {
      summary: 'A FreshRSS server (a free, self-hosted RSS and Atom feed aggregator) on the official image. A plain composable http workload that keeps its feeds and articles in SQLite on a PersistentVolume by default — no external database. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The FreshRSS server. Keeps its SQLite database at /var/www/FreshRSS/data on the volume; baseUrl is the public URL. Point it at external PostgreSQL/MySQL via the setup wizard to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='freshrss'),
          d.arg('image', d.T.string, default='docker.io/freshrss/freshrss:1.29.1'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('baseUrl', d.T.string, example='https://rss.example.com'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/freshrss/server.libsonnet' },
      },
    },
    flatnotes: {
      summary: 'A flatnotes server (a self-hosted, database-less note-taking app that stores everything as flat markdown files) on the official image. A plain composable http workload — your notes live on a PersistentVolume, no external database. kurly authors no Secret; the username, password, and secret key come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The flatnotes server. Notes live at /data on the volume. secretName holds FLATNOTES_USERNAME, FLATNOTES_PASSWORD, and FLATNOTES_SECRET_KEY (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='flatnotes'),
          d.arg('image', d.T.string, default='docker.io/dullage/flatnotes:v5.5.4'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='flatnotes-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/flatnotes/server.libsonnet' },
      },
    },
    trilium: {
      summary: 'A TriliumNext Notes server (a hierarchical note-taking application for building personal knowledge bases) on the official image. A plain composable http workload that keeps its notes in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web app and sync API on :8080.',
      stages: {
        server: d.fn('The TriliumNext server. Keeps notes in SQLite at /home/node/trilium-data on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='trilium'),
          d.arg('image', d.T.string, default='ghcr.io/triliumnext/trilium:v0.104.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/trilium/server.libsonnet' },
      },
    },
    silverbullet: {
      summary: 'A SilverBullet server (an extensible, self-hosted markdown notebook / personal knowledge base) on the official image. A plain composable http workload — your notes are plain markdown files on a PersistentVolume, no external database. kurly authors no Secret; SB_USER comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The SilverBullet server. Your markdown space lives at /space on the volume. secretName holds SB_USER (user:password, envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='silverbullet'),
          d.arg('image', d.T.string, default='ghcr.io/silverbulletmd/silverbullet:2.9.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='silverbullet-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/silverbullet/server.libsonnet' },
      },
    },
    'code-server': {
      summary: 'A code-server instance (VS Code running in the browser, on a remote server) on the official image. A plain composable http workload — your projects, extensions, and settings live on a PersistentVolume. kurly authors no Secret; PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The code-server editor. Workspace, extensions, and settings at /home/coder on the volume. secretName holds PASSWORD (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='code-server'),
          d.arg('image', d.T.string, default='docker.io/codercom/code-server:4.129.0'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='code-server-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/code-server/server.libsonnet' },
      },
    },
    beszel: {
      summary: 'A Beszel hub (a lightweight server-monitoring dashboard) on the official image. A plain composable http workload that keeps its data in SQLite on a PersistentVolume — no external database. Beszel agents run on the monitored machines and report to this hub. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8090.',
      stages: {
        server: d.fn('The Beszel hub. Keeps its SQLite data at /beszel_data on the volume. Compose an exposure onto the HTTP port; agents on monitored hosts report to it.', [
          d.arg('name', d.T.string, default='beszel'),
          d.arg('image', d.T.string, default='ghcr.io/henrygd/beszel/beszel:0.18.7'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/beszel/server.libsonnet' },
      },
    },
    audiobookshelf: {
      summary: 'An Audiobookshelf server (a self-hosted audiobook and podcast server) on the official image. A plain composable http workload that keeps its config, metadata, and library on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Audiobookshelf server. Config at /config, metadata at /metadata, library at /audiobooks, all on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='audiobookshelf'),
          d.arg('image', d.T.string, default='ghcr.io/advplyr/audiobookshelf:2.35.1'),
          d.arg('storageSize', d.T.quantity, default='50Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/audiobookshelf/server.libsonnet' },
      },
    },
    navidrome: {
      summary: 'A Navidrome server (a modern music server and streamer, compatible with Subsonic/Airsonic clients) on the official image. A plain composable http workload that keeps its database on a PersistentVolume and reads a music library from /music on the same volume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :4533.',
      stages: {
        server: d.fn('The Navidrome server. Database at /data, music library at /music (read-only), both on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='navidrome'),
          d.arg('image', d.T.string, default='docker.io/deluan/navidrome:0.63.2'),
          d.arg('storageSize', d.T.quantity, default='50Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/navidrome/server.libsonnet' },
      },
    },
    kavita: {
      summary: 'A Kavita server (a fast, cross-platform reading server for comics, manga, and ebooks) on the official image. A plain composable http workload that keeps its database on a PersistentVolume and serves a library from /library on the same volume — no external database. The .NET app writes temp files to the rootfs, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :5000.',
      stages: {
        server: d.fn('The Kavita server. Database and settings at /kavita/config, library at /library, both on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='kavita'),
          d.arg('image', d.T.string, default='docker.io/jvmilazz0/kavita:0.9.0.2'),
          d.arg('storageSize', d.T.quantity, default='20Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/kavita/server.libsonnet' },
      },
    },
    komga: {
      summary: 'A Komga server (a media server for comics, manga, and digital books) on the official image. A plain composable http workload that keeps its database on a PersistentVolume and serves a library from /books on the same volume — no external database. The Java app writes temp files to the rootfs, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :25600.',
      stages: {
        server: d.fn('The Komga server. Database at /config, library at /books, both on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='komga'),
          d.arg('image', d.T.string, default='docker.io/gotson/komga:1.25.0'),
          d.arg('storageSize', d.T.quantity, default='20Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/komga/server.libsonnet' },
      },
    },
    microbin: {
      summary: 'A MicroBin server (a tiny, self-contained pastebin and file-sharing service). A plain composable http workload that keeps its pastes and uploaded files on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :8080.',
      stages: {
        server: d.fn('The MicroBin server. Keeps pastes and files at /app/microbin_data on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='microbin'),
          d.arg('image', d.T.string, default='docker.io/danielszabo99/microbin:v2.1.4'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/microbin/server.libsonnet' },
      },
    },
    'stirling-pdf': {
      summary: 'A Stirling-PDF server (a locally-hosted web toolkit for splitting, merging, converting, and editing PDFs) on the official image. A plain composable http workload — it processes files in memory and keeps configuration on a PersistentVolume, no external database. The image runs LibreOffice and writes the root filesystem, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The Stirling-PDF server. Keeps configuration and custom files at /configs on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='stirling-pdf'),
          d.arg('image', d.T.string, default='docker.io/stirlingtools/stirling-pdf:2.14.2'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet' },
      },
    },
    dashy: {
      summary: 'A Dashy server (a highly customizable, self-hosted dashboard for your services) on the official image. A plain composable http workload — its configuration lives on a PersistentVolume, no external database. The image rebuilds assets on a config change and writes the root filesystem, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The Dashy server. Configuration lives at /app/user-data/conf.yml on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='dashy'),
          d.arg('image', d.T.string, default='docker.io/lissy93/dashy:4.4.7'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/dashy/server.libsonnet' },
      },
    },
    homer: {
      summary: 'A Homer server (a simple, static dashboard for your self-hosted services) on the official image. A plain composable http workload — its configuration and custom assets live on a PersistentVolume, no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the dashboard on :8080.',
      stages: {
        server: d.fn('The Homer server. Configuration and custom assets live at /www/assets on the volume (edit config.yml there; the image seeds defaults via INIT_ASSETS). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='homer'),
          d.arg('image', d.T.string, default='docker.io/b4bz/homer:v26.4.2'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '64Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/homer/server.libsonnet' },
      },
    },
    excalidraw: {
      summary: 'An Excalidraw server (a virtual hand-drawn-style whiteboard) on the official image. Excalidraw is a client-side app — the container serves static assets and drawings live in the browser — so this workload is stateless and scales via replicas. The nginx image binds :80 as root, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Serves on :80.',
      stages: {
        server: d.fn('The Excalidraw static server on :80 (stateless — scale via replicas). The image tag is an immutable sha (Excalidraw ships no semver tags). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='excalidraw'),
          d.arg('image', d.T.string, default='docker.io/excalidraw/excalidraw:sha-4bfc5bb'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet' },
      },
    },
    dokuwiki: {
      summary: 'A DokuWiki server (a simple, database-less wiki that stores its pages as flat files) on the official image. A plain composable http workload — all content lives on a PersistentVolume, no external database. The nginx + PHP-FPM image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The DokuWiki server. All content lives at /storage on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='dokuwiki'),
          d.arg('image', d.T.string, default='docker.io/dokuwiki/dokuwiki:2025-05-14b'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet' },
      },
    },
    readeck: {
      summary: 'A Readeck server (a self-hosted read-it-later and web-bookmarking tool that saves clean, readable copies of pages). A plain composable http workload that keeps its bookmarks and saved articles in SQLite on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :8000.',
      stages: {
        server: d.fn('The Readeck server. Keeps its SQLite database and saved pages at /readeck on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='readeck'),
          d.arg('image', d.T.string, default='codeberg.org/readeck/readeck:0.22.3'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/readeck/server.libsonnet' },
      },
    },
    shiori: {
      summary: 'A Shiori server (a simple, self-hosted bookmarks manager with web-page archiving). A plain composable http workload that keeps its bookmarks and archived pages in SQLite on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :8080.',
      stages: {
        server: d.fn('The Shiori server (runs `shiori serve`). Keeps its SQLite database and archives at /shiori on the volume. Point SHIORI_DATABASE_URL at external PostgreSQL/MySQL through env to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='shiori'),
          d.arg('image', d.T.string, default='ghcr.io/go-shiori/shiori:v1.8.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/shiori/server.libsonnet' },
      },
    },
    linkding: {
      summary: 'A linkding server (a minimal, self-hosted bookmark manager). A plain composable http workload that keeps its bookmarks in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :9090.',
      stages: {
        server: d.fn('The linkding server. Keeps bookmarks in SQLite at /etc/linkding/data on the volume. Point LD_DB_ENGINE at external PostgreSQL through env to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='linkding'),
          d.arg('image', d.T.string, default='docker.io/sissbruecker/linkding:1.45.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/linkding/server.libsonnet' },
      },
    },
    gotify: {
      summary: 'A Gotify server (a simple server for sending and receiving push notifications). A plain composable http workload that keeps its messages, apps, and clients in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web app and API on :80.',
      stages: {
        server: d.fn('The Gotify server. Keeps everything in SQLite at /app/data on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='gotify'),
          d.arg('image', d.T.string, default='docker.io/gotify/server:3.0.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/gotify/server.libsonnet' },
      },
    },
    ntfy: {
      summary: 'An ntfy server (send push notifications to your phone or desktop over simple HTTP). A plain composable http workload that keeps its message cache and user database in SQLite on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web app and pub/sub API on :80.',
      stages: {
        server: d.fn('The ntfy server (runs `serve`). Keeps its cache, auth db, and attachments at /var/lib/ntfy on the volume. baseUrl is the public URL (needed for the web app, attachments, iOS). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='ntfy'),
          d.arg('image', d.T.string, default='docker.io/binwiederhier/ntfy:v2.26.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('baseUrl', d.T.string, example='https://ntfy.example.com'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/ntfy/server.libsonnet' },
      },
    },
    memos: {
      summary: 'A Memos server (a lightweight, self-hosted notes and micro-blogging service). A plain composable http workload that keeps its notes in a SQLite database on a PersistentVolume — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the web UI and API on :5230.',
      stages: {
        server: d.fn('The Memos server. Keeps notes in SQLite at /var/opt/memos on the volume. Point MEMOS_DRIVER at external PostgreSQL through env to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='memos'),
          d.arg('image', d.T.string, default='docker.io/neosmemo/memos:0.29.1'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/memos/server.libsonnet' },
      },
    },
    overleaf: {
      summary: 'An Overleaf server (the Community Edition of the collaborative LaTeX editor) on the official monolith image, backed by an external MongoDB (a replica set — it uses transactions) and Redis, with projects and compiles on a PersistentVolume. kurly ships no MongoDB recipe; bring your own (Redis can be the valkey workload). The image spawns TeX compiles and writes across the root filesystem, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; OVERLEAF_MONGO_URL comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Overleaf server. redisHost defaults to a valkey named overleaf-cache; siteUrl is the public URL; appName the instance name. secretName holds OVERLEAF_MONGO_URL, pointing at a MongoDB replica set you provide (envFrom). Projects and compiles at /var/lib/overleaf. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='overleaf'),
          d.arg('image', d.T.string, default='docker.io/sharelatex/sharelatex:6.2.1'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('redisHost', d.T.string, default='overleaf-cache'),
          d.arg('siteUrl', d.T.string, example='https://latex.example.com'),
          d.arg('appName', d.T.string, default='Overleaf'),
          d.arg('secretName', d.T.string, default='overleaf-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/overleaf/server.libsonnet' },
      },
    },
    bigcapital: {
      summary: 'A Bigcapital deployment (self-hosted accounting and financial management) as three coordinated stages on the official images — server (the API), webapp (the front end), and gateway (the nginx entry). Backed by external MySQL/MariaDB, MongoDB, and Redis (kurly ships no MySQL/MongoDB recipe; bring your own). Run all three pointed at the same namePrefix and secretName; expose only the gateway. kurly authors no Secret; passwords and the JWT secret come from a provided Secret via envFrom.',
      stages: {
        server: d.fn('The Bigcapital API on :4000. dbHost points at a MySQL/MariaDB (system and tenant data), mongoHost at MongoDB, redisHost at Redis/valkey. baseUrl is the public URL. secretName holds SYSTEM_DB_PASSWORD, TENANT_DB_PASSWORD, and JWT_SECRET (envFrom). The gateway proxies to it.', [
          d.arg('namePrefix', d.T.string, default='bigcapital'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='docker.io/bigcapitalhq/server:v0.25.23'),
          d.arg('dbHost', d.T.string, default='bigcapital-mariadb'),
          d.arg('dbUser', d.T.string, default='bigcapital'),
          d.arg('mongoHost', d.T.string, default='bigcapital-mongo'),
          d.arg('redisHost', d.T.string, default='bigcapital-cache'),
          d.arg('baseUrl', d.T.string, example='https://accounting.example.com'),
          d.arg('secretName', d.T.string, default='bigcapital-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet' },
        webapp: d.fn('The Bigcapital front end (single-page web app) on :80. Stateless — scales via replicas. The gateway proxies to it.', [
          d.arg('namePrefix', d.T.string, default='bigcapital'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='docker.io/bigcapitalhq/webapp:v0.25.23'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet' },
        gateway: d.fn('The Bigcapital nginx entry on :80 — the stage you expose. Routes the browser to the webapp and /api to the server, which it reaches by Service names derived from namePrefix. Compose an exposure onto it.', [
          d.arg('namePrefix', d.T.string, default='bigcapital'),
          d.arg('name', d.T.string),
          d.arg('image', d.T.string, default='docker.io/bigcapitalhq/gateway:v0.25.23'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet' },
      },
    },
    twenty: {
      summary: 'A Twenty server (a modern, open-source CRM) as two stages — server (the web/API front end) and worker (background BullMQ jobs) — on the official image, backed by an external PostgreSQL and Redis. Pairs with a cnpg-cluster named twenty-db and a valkey named twenty-cache. kurly authors no Secret; PG_DATABASE_URL and APP_SECRET come from a provided Secret via envFrom. The server keeps local uploads on a ReadWriteOnce volume (one replica, recreated); move to S3 to scale out.',
      stages: {
        server: d.fn('The Twenty web/API front end on :3000. redisHost defaults to a valkey named twenty-cache; serverUrl is the public URL. secretName holds PG_DATABASE_URL (with the DB password) and APP_SECRET (envFrom). Local uploads at /app/packages/twenty-server/.local-storage. Run a worker alongside. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='twenty'),
          d.arg('image', d.T.string, default='docker.io/twentycrm/twenty:v2.22.0'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('redisHost', d.T.string, default='twenty-cache'),
          d.arg('serverUrl', d.T.string, example='https://crm.example.com'),
          d.arg('secretName', d.T.string, default='twenty-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/twenty/server.libsonnet' },
        worker: d.fn('The Twenty background worker (BullMQ jobs), same image and Secret as the server, no Service. redisHost/secretName match the server. Runs `yarn worker:prod`. Scales horizontally via replicas. A Twenty deployment needs at least one.', [
          d.arg('name', d.T.string, default='twenty-worker'),
          d.arg('image', d.T.string, default='docker.io/twentycrm/twenty:v2.22.0'),
          d.arg('redisHost', d.T.string, default='twenty-cache'),
          d.arg('secretName', d.T.string, default='twenty-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'worker', importPath: 'github.com/metio/kurly/workloads/twenty/worker.libsonnet' },
      },
    },
    sonarqube: {
      summary: 'A SonarQube server (continuous code-quality and static-analysis inspection) on the official Community image, backed by an external PostgreSQL, with data/extensions/search-index on a PersistentVolume. Pairs with a cnpg-cluster named sonarqube-db. Its embedded Elasticsearch needs the node vm.max_map_count >= 262144 (set on the node; kurly injects no privileged initContainer). kurly authors no Secret; SONAR_JDBC_PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :9000.',
      stages: {
        server: d.fn('The SonarQube server. dbHost/dbName/dbUser default to a cnpg-cluster named sonarqube-db (SONAR_JDBC_URL is built from them). secretName holds SONAR_JDBC_PASSWORD (envFrom). Data at /opt/sonarqube/data, extensions and logs on the volume. Requires node vm.max_map_count >= 262144. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='sonarqube'),
          d.arg('image', d.T.string, default='docker.io/library/sonarqube:26.7.0.124771-community'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='sonarqube-db-rw'),
          d.arg('dbName', d.T.string, default='sonarqube'),
          d.arg('dbUser', d.T.string, default='sonarqube'),
          d.arg('secretName', d.T.string, default='sonarqube-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet' },
      },
    },
    peertube: {
      summary: 'A PeerTube server (a decentralized, federated video platform) on the official image, backed by an external PostgreSQL and Redis, with videos/uploads/config on a PersistentVolume. Pairs with a cnpg-cluster named peertube-db and a valkey named peertube-cache. kurly authors no Secret; PEERTUBE_DB_PASSWORD, PEERTUBE_SECRET, and the initial root password come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :9000.',
      stages: {
        server: d.fn('The PeerTube server. dbHost/dbName/dbUser default to a cnpg-cluster named peertube-db; redisHost to a valkey named peertube-cache. webserverHost is the public hostname (required for federation). secretName holds PEERTUBE_DB_PASSWORD, PEERTUBE_SECRET, PT_INITIAL_ROOT_PASSWORD (envFrom). Videos/uploads at /data, config at /config. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='peertube'),
          d.arg('image', d.T.string, default='docker.io/chocobozzz/peertube:v8.2.2-trixie'),
          d.arg('storageSize', d.T.quantity, default='50Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='peertube-db-rw'),
          d.arg('dbName', d.T.string, default='peertube'),
          d.arg('dbUser', d.T.string, default='peertube'),
          d.arg('redisHost', d.T.string, default='peertube-cache'),
          d.arg('webserverHost', d.T.string, example='videos.example.com'),
          d.arg('secretName', d.T.string, default='peertube-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/peertube/server.libsonnet' },
      },
    },
    maybe: {
      summary: 'A Maybe server (a self-hosted personal finance and net-worth manager) backed by an external PostgreSQL and Redis, with Active Storage uploads on a PersistentVolume. Pairs with a cnpg-cluster named maybe-db and a valkey named maybe-cache. The Rails app writes under /rails, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. kurly authors no Secret; POSTGRES_PASSWORD and SECRET_KEY_BASE come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The Maybe server. dbHost/dbName/dbUser default to a cnpg-cluster named maybe-db; redisHost to a valkey named maybe-cache. secretName holds POSTGRES_PASSWORD and SECRET_KEY_BASE (envFrom). Uploads at /rails/storage. A separate Sidekiq worker can be added. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='maybe'),
          d.arg('image', d.T.string, default='ghcr.io/maybe-finance/maybe:0.1.0-alpha.6'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='maybe-db-rw'),
          d.arg('dbName', d.T.string, default='maybe'),
          d.arg('dbUser', d.T.string, default='maybe'),
          d.arg('redisHost', d.T.string, default='maybe-cache'),
          d.arg('secretName', d.T.string, default='maybe-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/maybe/server.libsonnet' },
      },
    },
    mautic: {
      summary: 'A Mautic server (open-source marketing automation) on the official Apache image, backed by an external MySQL/MariaDB, with configuration and media on a PersistentVolume. kurly ships no MySQL recipe — bring your own. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; MAUTIC_DB_PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Mautic server. dbHost/dbName/dbUser point at a MySQL/MariaDB you provide. siteUrl is the public URL; runCronJobs runs Mautic background jobs in-container. secretName holds MAUTIC_DB_PASSWORD (envFrom). Config at /var/www/html/config, media on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='mautic'),
          d.arg('image', d.T.string, default='docker.io/mautic/mautic:5.2.11-apache'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='mautic-db'),
          d.arg('dbName', d.T.string, default='mautic'),
          d.arg('dbUser', d.T.string, default='mautic'),
          d.arg('siteUrl', d.T.string, example='https://mautic.example.com'),
          d.arg('secretName', d.T.string, default='mautic-secrets'),
          d.arg('runCronJobs', d.T.bool, default=true),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mautic/server.libsonnet' },
      },
    },
    invoiceninja: {
      summary: 'An Invoice Ninja server (self-hosted invoicing, quotes, and payments) on the official image, backed by an external MySQL/MariaDB, with uploads and PDFs on a PersistentVolume. kurly ships no MySQL recipe — bring your own. The nginx + PHP-FPM image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DB_PASSWORD and APP_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Invoice Ninja server. dbHost/dbName/dbUser point at a MySQL/MariaDB you provide (DB_CONNECTION=mysql). appUrl is the public URL. secretName holds DB_PASSWORD and APP_KEY (envFrom). Uploads/PDFs at /var/www/html/storage. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='invoiceninja'),
          d.arg('image', d.T.string, default='docker.io/invoiceninja/invoiceninja:5.13.26'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='invoiceninja-db'),
          d.arg('dbName', d.T.string, default='invoiceninja'),
          d.arg('dbUser', d.T.string, default='invoiceninja'),
          d.arg('appUrl', d.T.string, example='https://invoicing.example.com'),
          d.arg('secretName', d.T.string, default='invoiceninja-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet' },
      },
    },
    'paperless-ngx': {
      summary: 'A Paperless-ngx server (scan, index, and archive documents with OCR and full-text search) backed by an external PostgreSQL and Redis, with its data/media/consume/export trees on a PersistentVolume. The image runs the web server and Celery workers together. Pairs with a cnpg-cluster named paperless-db and a valkey named paperless-cache. The entrypoint writes to the root filesystem, so read-only-rootfs is relaxed while non-root and dropped capabilities stay. kurly authors no Secret; secrets come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8000.',
      stages: {
        server: d.fn('The Paperless-ngx server. dbHost/dbName/dbUser default to a cnpg-cluster named paperless-db; redisHost to a valkey named paperless-cache. url is the public URL; adminUser the first-run admin. secretName holds PAPERLESS_DBPASS, PAPERLESS_SECRET_KEY, and PAPERLESS_ADMIN_PASSWORD (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='paperless-ngx'),
          d.arg('image', d.T.string, default='ghcr.io/paperless-ngx/paperless-ngx:2.20.15'),
          d.arg('storageSize', d.T.quantity, default='20Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='paperless-db-rw'),
          d.arg('dbName', d.T.string, default='paperless'),
          d.arg('dbUser', d.T.string, default='paperless'),
          d.arg('redisHost', d.T.string, default='paperless-cache'),
          d.arg('url', d.T.string, example='https://paperless.example.com'),
          d.arg('adminUser', d.T.string, default='admin'),
          d.arg('secretName', d.T.string, default='paperless-ngx-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet' },
      },
    },
    wger: {
      summary: 'A wger server (a self-hosted workout, nutrition, and body-weight manager) on the official all-in-one image, backed by an external PostgreSQL and Redis, with uploaded media on a PersistentVolume. Pairs with a cnpg-cluster named wger-db and a valkey named wger-cache. The image runs nginx + uWSGI + Celery and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DJANGO_DB_PASSWORD and SECRET_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The wger server. dbHost/dbName/dbUser default to a cnpg-cluster named wger-db; redisHost to a valkey named wger-cache. siteUrl is the public URL. secretName holds DJANGO_DB_PASSWORD and SECRET_KEY (envFrom). Media at /home/wger/media on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='wger'),
          d.arg('image', d.T.string, default='docker.io/wger/server:2.6.0'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='wger-db-rw'),
          d.arg('dbName', d.T.string, default='wger'),
          d.arg('dbUser', d.T.string, default='wger'),
          d.arg('redisHost', d.T.string, default='wger-cache'),
          d.arg('siteUrl', d.T.string, example='https://wger.example.com'),
          d.arg('secretName', d.T.string, default='wger-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/wger/server.libsonnet' },
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
    karakeep: {
      summary: 'A Karakeep server (a self-hosted "bookmark everything" app, formerly Hoarder: save links, notes and images and search them with AI tagging) on the official image; its SQLite database and stored assets live on a PersistentVolume. Expects two companion side services it does not bundle: a Meilisearch instance (MEILI_ADDR + MEILI_MASTER_KEY) and a headless Chrome (BROWSER_WEB_URL). kurly authors no Secret; NEXTAUTH_SECRET, MEILI_MASTER_KEY and AI provider keys come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The Karakeep server. nextauthUrl is the public URL. meiliAddr/browserWebUrl point at the Meilisearch and headless-Chrome companions. secretName holds NEXTAUTH_SECRET, MEILI_MASTER_KEY and AI provider keys (envFrom). Database and assets at /data. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='karakeep'),
          d.arg('image', d.T.string, default='ghcr.io/karakeep-app/karakeep:v0.32.0'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('nextauthUrl', d.T.string, example='https://bookmarks.example.com'),
          d.arg('meiliAddr', d.T.string, default='http://meilisearch:7700'),
          d.arg('browserWebUrl', d.T.string, default='http://chrome:9222'),
          d.arg('secretName', d.T.string, default='karakeep-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/karakeep/server.libsonnet' },
      },
    },
    homarr: {
      summary: 'A Homarr server (a sleek, self-hosted dashboard for your homelab) on the official image; its SQLite database and config live on a PersistentVolume, so it needs no external database. kurly authors no Secret; SECRET_ENCRYPTION_KEY comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :7575.',
      stages: {
        server: d.fn('The Homarr server. secretName holds SECRET_ENCRYPTION_KEY (a 64-character hex string, envFrom). Data at /appdata. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='homarr'),
          d.arg('image', d.T.string, default='ghcr.io/homarr-labs/homarr:v1.71.0'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='homarr-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/homarr/server.libsonnet' },
      },
    },
    mattermost: {
      summary: 'A Mattermost server (a self-hosted, open-source team messaging platform à la Slack) on the Team Edition image, backed by an external PostgreSQL, with file uploads on a PersistentVolume. Pairs with a cnpg-cluster named mattermost-db. kurly authors no Secret; MM_SQLSETTINGS_DATASOURCE comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated (point the file store at S3 to scale out). Serves on :8065.',
      stages: {
        server: d.fn('The Mattermost server. siteUrl is the public URL. secretName holds MM_SQLSETTINGS_DATASOURCE (envFrom). Uploads at /mattermost/data. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='mattermost'),
          d.arg('image', d.T.string, default='docker.io/mattermost/mattermost-team-edition:11.8.4'),
          d.arg('storageSize', d.T.quantity, default='20Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('siteUrl', d.T.string, example='https://chat.example.com'),
          d.arg('secretName', d.T.string, default='mattermost-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mattermost/server.libsonnet' },
      },
    },
    rocketchat: {
      summary: 'A Rocket.Chat server (a self-hosted, open-source team chat platform) on the official image, backed by an external MongoDB replica set (Rocket.Chat requires the oplog). Pairs with a mongodb-cluster named rocketchat-db. kurly authors no Secret; MONGO_URL and MONGO_OPLOG_URL come from a provided Secret via envFrom. Stateless (uploads live in MongoDB GridFS): a plain rolling Deployment. Serves on :3000.',
      stages: {
        server: d.fn('The Rocket.Chat server. rootUrl is the public URL. secretName holds MONGO_URL and MONGO_OPLOG_URL (envFrom); MongoDB MUST be a replica set. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='rocketchat'),
          d.arg('image', d.T.string, default='docker.io/rocketchat/rocket.chat:8.6.1'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('rootUrl', d.T.string, example='https://chat.example.com'),
          d.arg('secretName', d.T.string, default='rocketchat-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet' },
      },
    },
    wekan: {
      summary: 'A Wekan server (a self-hosted, open-source kanban board à la Trello) on the official image, backed by an external MongoDB. Pairs with a mongodb-cluster named wekan-db. kurly authors no Secret; MONGO_URL comes from a provided Secret via envFrom. Stateless (attachments live in MongoDB GridFS): a plain rolling Deployment. Serves on :8080.',
      stages: {
        server: d.fn('The Wekan server. rootUrl is the public URL. secretName holds MONGO_URL (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='wekan'),
          d.arg('image', d.T.string, default='docker.io/wekan/wekan:v10.03'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('rootUrl', d.T.string, example='https://boards.example.com'),
          d.arg('secretName', d.T.string, default='wekan-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/wekan/server.libsonnet' },
      },
    },
    activepieces: {
      summary: 'An Activepieces server (a self-hosted, open-source no-code automation / workflow builder à la Zapier) on the official all-in-one image, backed by an external PostgreSQL and Redis. Pairs with a cnpg-cluster named activepieces-db and a Redis. kurly authors no Secret; AP_POSTGRES_*, AP_REDIS_*, AP_ENCRYPTION_KEY and AP_JWT_SECRET come from a provided Secret via envFrom. Stateless: a plain rolling Deployment. Serves on :80.',
      stages: {
        server: d.fn('The Activepieces server. frontendUrl is the public URL (webhook URLs derive from it). secretName holds AP_POSTGRES_*, AP_REDIS_*, AP_ENCRYPTION_KEY and AP_JWT_SECRET (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='activepieces'),
          d.arg('image', d.T.string, default='docker.io/activepieces/activepieces:0.86.3'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('frontendUrl', d.T.string, example='https://flows.example.com'),
          d.arg('secretName', d.T.string, default='activepieces-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/activepieces/server.libsonnet' },
      },
    },
    automatisch: {
      summary: 'An Automatisch server (a self-hosted, open-source business-automation / workflow tool, an open alternative to Zapier) on the official image, backed by an external PostgreSQL and Redis. Two stages: a web server (HTTP :3000) and a background worker that runs the flow executions the server enqueues onto Redis. Pairs with a cnpg-cluster named automatisch-db and a Redis. kurly authors no Secret; the PostgreSQL/Redis connection and the ENCRYPTION_KEY / WEBHOOK_SECRET_KEY / APP_SECRET_KEY come from a provided Secret via envFrom, shared by both stages. Stateless.',
      stages: {
        server: d.fn('The Automatisch web server. secretName holds the PostgreSQL/Redis connection and the ENCRYPTION_KEY / WEBHOOK_SECRET_KEY / APP_SECRET_KEY (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='automatisch'),
          d.arg('image', d.T.string, default='ghcr.io/automatisch/automatisch:0.15.0'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('secretName', d.T.string, default='automatisch-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/automatisch/server.libsonnet' },
        worker: d.fn("The Automatisch background worker (runs the flow executions the server enqueues onto Redis). Shares the server's Secret via envFrom. No Service.", [
          d.arg('name', d.T.string, default='automatisch-worker'),
          d.arg('image', d.T.string, default='ghcr.io/automatisch/automatisch:0.15.0'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('secretName', d.T.string, default='automatisch-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'worker', importPath: 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet' },
      },
    },
    spegel: {
      summary: "Spegel — a stateless, cluster-local OCI registry mirror (spegel.dev). A DaemonSet that serves image layers already present in each node's containerd content store to its peers over a peer-to-peer router, so a pull satisfied by any node never leaves the cluster; an init container writes containerd's registry-mirror config to pull through the local mirror first. Genuinely node-level infrastructure, so it authors its manifests directly (DaemonSet + init container + hostPath containerd socket/content, a NodePort the kubelet reaches the mirror on, and a headless Service peers bootstrap against via DNS) rather than composing a base kind. namespace is load-bearing: the bootstrap DNS name embeds it, so it must match where you deploy. Runs as root with hostPath mounts (the socket is root-owned); the posture is hardened as far as that allows. kurly features do not apply.",
      stages: {
        mirror: d.fn("The Spegel DaemonSet and its Services. namespace MUST match the deploy namespace (the peer-bootstrap DNS name embeds it). containerdSock/containerdContentPath/containerdRegistryConfigPath point at the node's containerd; the kubelet reaches the local mirror at both registryHostPort (straight to the local pod) and registryNodePort (through kube-proxy), so set registryHostPort=null where host ports are forbidden. dataDir persists routing state (null to disable).", [
          d.arg('name', d.T.string, default='spegel'),
          d.arg('namespace', d.T.string, default='spegel'),
          d.arg('image', d.T.string, default='ghcr.io/spegel-org/spegel:v0.7.4'),
          d.arg('containerdSock', d.T.string, default='/run/containerd/containerd.sock'),
          d.arg('containerdContentPath', d.T.string, default='/var/lib/containerd/io.containerd.content.v1.content'),
          d.arg('containerdRegistryConfigPath', d.T.string, default='/etc/containerd/certs.d'),
          d.arg('containerdNamespace', d.T.string, default='k8s.io'),
          d.arg('registryPort', d.T.int, default=5000),
          d.arg('registryHostPort', d.T.int, default=30020),
          d.arg('registryNodePort', d.T.int, default=30021),
          d.arg('routerPort', d.T.int, default=5001),
          d.arg('metricsPort', d.T.int, default=9090),
          d.arg('dataDir', d.T.string, default='/var/lib/spegel'),
          d.arg('logLevel', d.T.string, default='INFO'),
          d.arg('resolveTags', d.T.bool, default=true),
          d.arg('mirrorResolveRetries', d.T.int, default=3),
          d.arg('mirrorResolveTimeout', d.T.string, default='20ms'),
          d.arg('debugWeb', d.T.bool, default=false),
          d.arg('clusterDomain', d.T.string, default='cluster.local'),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '128Mi' } }),
          d.arg('tolerations', d.T.array, default=[{ operator: 'Exists' }]),
          d.arg('nodeSelector', d.T.object, default={ 'kubernetes.io/os': 'linux' }),
          d.arg('affinity', d.T.object),
          d.arg('priorityClassName', d.T.string, example='system-node-critical'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'daemon', importPath: 'github.com/metio/kurly/workloads/spegel/mirror.libsonnet' },
      },
    },
    pilos: {
      summary: 'A PILOS server (an open-source, Laravel-based front-end for BigBlueButton from TH Mittelhessen: room and meeting management with LDAP/OIDC support) on the official all-in-one image (nginx + php-fpm), backed by an external PostgreSQL and Redis, with uploaded assets on a PersistentVolume. It reaches an existing BigBlueButton server over the network; kurly does not run BBB itself. Pairs with a cnpg-cluster named pilos-db and a Redis. kurly authors no Secret; the database/Redis/APP_KEY/BBB settings come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated; the bundled nginx master needs root and a writable rootfs. Serves on :80.',
      stages: {
        server: d.fn('The PILOS server. secretName holds the database/Redis/APP_KEY/BBB settings (envFrom). Uploaded assets at /var/www/html/storage/app. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='pilos'),
          d.arg('image', d.T.string, default='docker.io/pilos/pilos:4.17.0'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='pilos-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/pilos/server.libsonnet' },
      },
    },
    greenlight: {
      summary: 'A Greenlight 3 server (the official BigBlueButton front-end: a Rails app for scheduling and joining BBB rooms and meetings) on the official image, backed by an external PostgreSQL and Redis. It reaches an existing BigBlueButton server over the network; kurly does not run BBB itself. Pairs with a cnpg-cluster named greenlight-db and a Redis. kurly authors no Secret; DATABASE_URL, REDIS_URL, SECRET_KEY_BASE and the BIGBLUEBUTTON_* endpoint/secret come from a provided Secret via envFrom. Stateless (recordings live on the BBB server): a plain rolling Deployment. Serves on :3000.',
      stages: {
        server: d.fn('The Greenlight server. secretName holds DATABASE_URL, REDIS_URL, SECRET_KEY_BASE and the BIGBLUEBUTTON_ENDPOINT/BIGBLUEBUTTON_SECRET (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='greenlight'),
          d.arg('image', d.T.string, default='docker.io/bigbluebutton/greenlight:v3.8.2.3'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('secretName', d.T.string, default='greenlight-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/greenlight/server.libsonnet' },
      },
    },
    docmost: {
      summary: 'A Docmost server (a self-hosted, open-source collaborative wiki and documentation platform) on the official image, backed by an external PostgreSQL and Redis, with attachments on a PersistentVolume. Pairs with a cnpg-cluster named docmost-db and a Redis. kurly authors no Secret; DATABASE_URL, REDIS_URL and APP_SECRET come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :3000.',
      stages: {
        server: d.fn('The Docmost server. appUrl is the public URL. secretName holds DATABASE_URL, REDIS_URL and APP_SECRET (envFrom). Attachments at /app/data/storage; point STORAGE_DRIVER at S3 to scale past the single writer. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='docmost'),
          d.arg('image', d.T.string, default='docker.io/docmost/docmost:0.95.0'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('appUrl', d.T.string, example='https://wiki.example.com'),
          d.arg('secretName', d.T.string, default='docmost-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/docmost/server.libsonnet' },
      },
    },
    bugsink: {
      summary: 'A Bugsink server (a self-hosted, Sentry-compatible error tracker: it ingests the same events your existing Sentry SDKs emit) on the official image, backed by an external PostgreSQL or MySQL. Pairs with a cnpg-cluster named bugsink-db. kurly authors no Secret; DATABASE_URL and SECRET_KEY come from a provided Secret via envFrom. Stateless (events live in the DB): a plain rolling Deployment. Serves on :8000.',
      stages: {
        server: d.fn('The Bugsink server. baseUrl is the public URL (validated Host header); behindHttps toggles secure-cookie/HTTPS handling. secretName holds DATABASE_URL and SECRET_KEY (envFrom). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='bugsink'),
          d.arg('image', d.T.string, default='docker.io/bugsink/bugsink:2.4.0'),
          d.arg('replicas', d.T.int, default=2),
          d.arg('baseUrl', d.T.string, example='https://errors.example.com'),
          d.arg('behindHttps', d.T.bool, default=true),
          d.arg('secretName', d.T.string, default='bugsink-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/bugsink/server.libsonnet' },
      },
    },
    blinko: {
      summary: 'A Blinko server (a self-hosted, AI-powered note-taking app for quickly capturing ideas) on the official image, backed by an external PostgreSQL, with uploads on a PersistentVolume. Pairs with a cnpg-cluster named blinko-db. kurly authors no Secret; DATABASE_URL and NEXTAUTH_SECRET come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :1111.',
      stages: {
        server: d.fn('The Blinko server. nextauthUrl is the public URL. secretName holds DATABASE_URL (with the DB password) and NEXTAUTH_SECRET (envFrom). Uploads at /app/.blinko. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='blinko'),
          d.arg('image', d.T.string, default='docker.io/blinkospace/blinko:1.8.8'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('nextauthUrl', d.T.string, example='https://notes.example.com'),
          d.arg('secretName', d.T.string, default='blinko-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/blinko/server.libsonnet' },
      },
    },
    answer: {
      summary: 'An Apache Answer server (a self-hosted Q&A platform for a community knowledge base, à la Stack Overflow) on the official image. A plain composable http workload — with the SQLite backend its data and uploads live on a PersistentVolume, no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80. Configure external PostgreSQL/MySQL via the installer to scale out.',
      stages: {
        server: d.fn('The Apache Answer server. Data and uploads at /data on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='answer'),
          d.arg('image', d.T.string, default='docker.io/apache/answer:v2.0.1'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/answer/server.libsonnet' },
      },
    },
    photoprism: {
      summary: 'A PhotoPrism server (an AI-powered, self-hosted photo-management app with face recognition and automatic tagging) on the official image. A plain composable http workload — with the SQLite backend its database, cache, and originals live on a PersistentVolume, no external database. The image runs TensorFlow indexing and writes the rootfs, relaxing read-only-rootfs while keeping non-root and dropped capabilities. kurly authors no Secret; PHOTOPRISM_ADMIN_PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :2342.',
      stages: {
        server: d.fn('The PhotoPrism server. Storage at /photoprism/storage, originals at /photoprism/originals, both on the volume. siteUrl is the public URL (keep the trailing /). secretName holds PHOTOPRISM_ADMIN_PASSWORD (envFrom). Point PHOTOPRISM_DATABASE_DRIVER at external MariaDB (mysql-cluster) to scale out. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='photoprism'),
          d.arg('image', d.T.string, default='docker.io/photoprism/photoprism:260601'),
          d.arg('storageSize', d.T.quantity, default='50Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('siteUrl', d.T.string, example='https://photos.example.com/'),
          d.arg('adminUser', d.T.string, default='admin'),
          d.arg('secretName', d.T.string, default='photoprism-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/photoprism/server.libsonnet' },
      },
    },
    lychee: {
      summary: 'A Lychee server (a self-hosted photo-management and gallery system) on the official image. A plain composable http workload — with the SQLite backend its config, database, and photos live on a PersistentVolume, no external database. The nginx + PHP-FPM image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; APP_KEY comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Lychee server. Photos at /uploads, config at /conf, symlinks at /sym, all on the volume. appUrl is the public URL. secretName holds APP_KEY (envFrom). Point DB_CONNECTION at external MySQL/PostgreSQL to scale past SQLite. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='lychee'),
          d.arg('image', d.T.string, default='docker.io/lycheeorg/lychee:v7.7.1'),
          d.arg('storageSize', d.T.quantity, default='20Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('appUrl', d.T.string, example='https://photos.example.com'),
          d.arg('secretName', d.T.string, default='lychee-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/lychee/server.libsonnet' },
      },
    },
    commafeed: {
      summary: 'A CommaFeed server (a self-hosted Google Reader-style RSS/Atom feed reader) on the official image. A plain composable http workload — the H2 variant keeps its feeds in an embedded database on a PersistentVolume, no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8082. Use the PostgreSQL image variant to scale past the embedded DB.',
      stages: {
        server: d.fn('The CommaFeed server (H2 variant). Keeps its embedded database at /commafeed/data on the volume. Switch to the -postgresql image and point CF_APP_DATABASE at a cnpg-cluster to scale out. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='commafeed'),
          d.arg('image', d.T.string, default='docker.io/athou/commafeed:7.2.0-h2'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/commafeed/server.libsonnet' },
      },
    },
    glitchtip: {
      summary: 'A GlitchTip deployment (an open-source, Sentry-compatible error-tracking and performance-monitoring platform) as two stages — server (the web/ingest API) and worker (the Celery worker with beat) — on the official image, backed by an external PostgreSQL and Redis. Pairs with a cnpg-cluster named glitchtip-db and a valkey named glitchtip-cache. kurly authors no Secret; DATABASE_URL and SECRET_KEY come from a provided Secret via envFrom. The server is stateless and scales via replicas.',
      stages: {
        server: d.fn('The GlitchTip web/ingest API on :8080. redisHost defaults to a valkey named glitchtip-cache; domain is the public URL. secretName holds DATABASE_URL (with the DB password) and SECRET_KEY (envFrom). Run a worker alongside. Scales via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='glitchtip'),
          d.arg('image', d.T.string, default='docker.io/glitchtip/glitchtip:v6.2.2'),
          d.arg('redisHost', d.T.string, default='glitchtip-cache'),
          d.arg('domain', d.T.string, example='https://errors.example.com'),
          d.arg('secretName', d.T.string, default='glitchtip-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet' },
        worker: d.fn('The GlitchTip Celery worker (with beat scheduler), same image and Secret as the server, no Service. redisHost/secretName match the server. Runs ./bin/run-celery-with-beat.sh. Scales horizontally via replicas. A GlitchTip deployment needs at least one.', [
          d.arg('name', d.T.string, default='glitchtip-worker'),
          d.arg('image', d.T.string, default='docker.io/glitchtip/glitchtip:v6.2.2'),
          d.arg('redisHost', d.T.string, default='glitchtip-cache'),
          d.arg('secretName', d.T.string, default='glitchtip-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'worker', importPath: 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet' },
      },
    },
    wallabag: {
      summary: 'A wallabag server (a self-hosted read-it-later app that saves clean, readable copies of web pages) on the official image, backed by an external PostgreSQL, with saved images on a PersistentVolume. Pairs with a cnpg-cluster named wallabag-db. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; the DB password and app secret come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The wallabag server. dbHost/dbName/dbUser default to a cnpg-cluster named wallabag-db (SYMFONY__ENV__ prefix). domain is the public URL. secretName holds SYMFONY__ENV__DATABASE_PASSWORD and SYMFONY__ENV__SECRET (envFrom). Saved images on the volume. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='wallabag'),
          d.arg('image', d.T.string, default='docker.io/wallabag/wallabag:2.6.14'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='wallabag-db-rw'),
          d.arg('dbName', d.T.string, default='wallabag'),
          d.arg('dbUser', d.T.string, default='wallabag'),
          d.arg('domain', d.T.string, example='https://read.example.com'),
          d.arg('secretName', d.T.string, default='wallabag-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/wallabag/server.libsonnet' },
      },
    },
    monica: {
      summary: 'A Monica server (a self-hosted personal relationship manager) on the official image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with uploads on a PersistentVolume. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DB_PASSWORD and APP_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Monica server. dbHost/dbName/dbUser point at a MySQL/MariaDB (e.g. mysql-cluster). appUrl is the public URL. secretName holds DB_PASSWORD and APP_KEY (envFrom). Uploads at /var/www/html/storage. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='monica'),
          d.arg('image', d.T.string, default='docker.io/library/monica:4.1.2-apache'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='monica-db'),
          d.arg('dbName', d.T.string, default='monica'),
          d.arg('dbUser', d.T.string, default='monica'),
          d.arg('appUrl', d.T.string, example='https://monica.example.com'),
          d.arg('secretName', d.T.string, default='monica-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/monica/server.libsonnet' },
      },
    },
    fider: {
      summary: 'A Fider server (an open-source platform to collect and prioritize customer feedback) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. Pairs with a cnpg-cluster named fider-db. kurly authors no Secret; DATABASE_URL, JWT_SECRET, and SMTP creds come from a provided Secret via envFrom. Serves on :3000.',
      stages: {
        server: d.fn('The Fider server. baseUrl is the public URL. secretName holds DATABASE_URL (with the DB password), JWT_SECRET, and EMAIL_* (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='fider'),
          d.arg('image', d.T.string, default='docker.io/getfider/fider:v0.36.0'),
          d.arg('baseUrl', d.T.string, example='https://feedback.example.com'),
          d.arg('secretName', d.T.string, default='fider-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/fider/server.libsonnet' },
      },
    },
    'firefly-iii': {
      summary: 'A Firefly III server (a free, self-hosted personal-finance manager) on the official image, backed by an external PostgreSQL, with uploads on a PersistentVolume. Pairs with a cnpg-cluster named firefly-iii-db. The Apache + PHP image starts as root and binds :8080, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DB_PASSWORD and APP_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The Firefly III server. dbHost/dbName/dbUser default to a cnpg-cluster named firefly-iii-db. appUrl is the public URL. secretName holds DB_PASSWORD and APP_KEY (a 32-char key, envFrom). Uploads at /var/www/html/storage. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='firefly-iii'),
          d.arg('image', d.T.string, default='docker.io/fireflyiii/core:version-6.6.6'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='firefly-iii-db-rw'),
          d.arg('dbName', d.T.string, default='firefly'),
          d.arg('dbUser', d.T.string, default='firefly'),
          d.arg('appUrl', d.T.string, example='https://finance.example.com'),
          d.arg('secretName', d.T.string, default='firefly-iii-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/firefly-iii/server.libsonnet' },
      },
    },
    mediawiki: {
      summary: 'A MediaWiki server (the wiki engine behind Wikipedia) on the official image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with uploaded files on a PersistentVolume. Configured by a LocalSettings.php mounted from a Secret (it holds the DB password and secret key). The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The MediaWiki server. Uploaded files at /var/www/html/images on the volume. Mount a LocalSettings.php at /var/www/html/LocalSettings.php from a Secret (DB creds + secret key). Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='mediawiki'),
          d.arg('image', d.T.string, default='docker.io/library/mediawiki:1.45.4'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet' },
      },
    },
    roundcube: {
      summary: 'A Roundcube server (a browser-based IMAP webmail client) on the official image. A plain composable http workload that connects to an external IMAP/SMTP mail server (e.g. the mailu workload) and keeps its own state in SQLite on a PersistentVolume — no external database. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Roundcube server. imapHost/smtpHost point at the mail server (e.g. ssl://mail.example.com:993). Keeps contacts/preferences in SQLite at /var/roundcube/db. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='roundcube'),
          d.arg('image', d.T.string, default='docker.io/roundcube/roundcubemail:1.7.2-apache'),
          d.arg('storageSize', d.T.quantity, default='1Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('imapHost', d.T.string, example='ssl://mail.example.com:993'),
          d.arg('smtpHost', d.T.string, example='tls://mail.example.com:587'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/roundcube/server.libsonnet' },
      },
    },
    shlink: {
      summary: 'A Shlink server (a self-hosted URL shortener with a REST API and rich analytics) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. Pairs with a cnpg-cluster named shlink-db. kurly authors no Secret; DB_PASSWORD (and optionally the GeoLite key) come from a provided Secret via envFrom. Serves on :8080.',
      stages: {
        server: d.fn('The Shlink server. dbHost/dbName/dbUser default to a cnpg-cluster named shlink-db. defaultDomain is the short-URL domain. secretName holds DB_PASSWORD (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='shlink'),
          d.arg('image', d.T.string, default='docker.io/shlinkio/shlink:5.1.5'),
          d.arg('dbHost', d.T.string, default='shlink-db-rw'),
          d.arg('dbName', d.T.string, default='shlink'),
          d.arg('dbUser', d.T.string, default='shlink'),
          d.arg('defaultDomain', d.T.string, example='s.example.com'),
          d.arg('secretName', d.T.string, default='shlink-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/shlink/server.libsonnet' },
      },
    },
    rallly: {
      summary: 'A Rallly server (a self-hosted scheduling and group-poll tool for finding the best date to meet) on the official image, backed by an external PostgreSQL. Stateless — its state lives in the database, so it can run several replicas. kurly authors no Secret; DATABASE_URL, SECRET_PASSWORD, and SMTP creds come from a provided Secret via envFrom. Pairs with a cnpg-cluster named rallly-db. Serves on :3000.',
      stages: {
        server: d.fn('The Rallly server. baseUrl is the public URL. secretName holds DATABASE_URL (with the DB password), SECRET_PASSWORD, and SMTP_* (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='rallly'),
          d.arg('image', d.T.string, default='ghcr.io/lukevella/rallly:4.11.1'),
          d.arg('baseUrl', d.T.string, example='https://rallly.example.com'),
          d.arg('secretName', d.T.string, default='rallly-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/rallly/server.libsonnet' },
      },
    },
    baserow: {
      summary: 'A Baserow server (an open-source, no-code database and Airtable alternative) on the official all-in-one image, which bundles the backend, frontend, Celery workers, and (by default) an embedded PostgreSQL and Redis — everything in /baserow/data, so a single instance needs nothing external. The image supervises multiple processes and writes the rootfs, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; the signing keys come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Baserow all-in-one server. Everything (embedded DB, Redis, uploads) at /baserow/data on the volume. publicUrl is the public URL. secretName holds BASEROW_SECRET_KEY and BASEROW_JWT_SIGNING_KEY (envFrom). Point DATABASE_*/REDIS_* at external services via env to scale out. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='baserow'),
          d.arg('image', d.T.string, default='docker.io/baserow/baserow:2.3.2'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('publicUrl', d.T.string, example='https://baserow.example.com'),
          d.arg('secretName', d.T.string, default='baserow-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/baserow/server.libsonnet' },
      },
    },
    nocodb: {
      summary: 'A NocoDB server (an open-source Airtable alternative that turns any SQL database into a smart spreadsheet) on the official image, backed by an external PostgreSQL for its metadata, with attachments on a PersistentVolume. kurly authors no Secret; NC_DB and NC_AUTH_JWT_SECRET come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8080.',
      stages: {
        server: d.fn('The NocoDB server. secretName holds NC_DB (a connection string with the DB password, point it at a cnpg-cluster) and NC_AUTH_JWT_SECRET (envFrom). publicUrl is the public URL. Attachments at /usr/app/data. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='nocodb'),
          d.arg('image', d.T.string, default='docker.io/nocodb/nocodb:2026.07.0'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('publicUrl', d.T.string, example='https://nocodb.example.com'),
          d.arg('secretName', d.T.string, default='nocodb-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/nocodb/server.libsonnet' },
      },
    },
    'snipe-it': {
      summary: 'A Snipe-IT server (a free IT asset and license management system) on the official image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with uploads on a PersistentVolume. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DB_PASSWORD and APP_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Snipe-IT server. dbHost/dbName/dbUser point at a MySQL/MariaDB (e.g. mysql-cluster). appUrl is the public URL. secretName holds DB_PASSWORD and APP_KEY (envFrom). Uploads at /var/lib/snipeit. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='snipe-it'),
          d.arg('image', d.T.string, default='docker.io/snipe/snipe-it:v8.6.3'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='snipe-it-db'),
          d.arg('dbName', d.T.string, default='snipeit'),
          d.arg('dbUser', d.T.string, default='snipeit'),
          d.arg('appUrl', d.T.string, example='https://assets.example.com'),
          d.arg('secretName', d.T.string, default='snipe-it-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet' },
      },
    },
    bookstack: {
      summary: 'A BookStack server (a simple, self-hosted platform for organising and storing documentation) on the maintained LinuxServer image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with config and uploads on a PersistentVolume. The LinuxServer s6 image runs as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; DB_PASS and APP_KEY come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The BookStack server. dbHost/dbName/dbUser point at a MySQL/MariaDB (e.g. mysql-cluster). appUrl is the public URL. secretName holds DB_PASS and APP_KEY (envFrom). Config/uploads at /config. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='bookstack'),
          d.arg('image', d.T.string, default='lscr.io/linuxserver/bookstack:26.05.2'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='bookstack-db'),
          d.arg('dbName', d.T.string, default='bookstack'),
          d.arg('dbUser', d.T.string, default='bookstack'),
          d.arg('appUrl', d.T.string, example='https://docs.example.com'),
          d.arg('secretName', d.T.string, default='bookstack-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/bookstack/server.libsonnet' },
      },
    },
    matomo: {
      summary: 'A Matomo server (a privacy-focused, self-hosted web-analytics platform — the open-source Google Analytics alternative) on the official image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with config and plugins on a PersistentVolume. The Apache + PHP image starts as root and binds :80, relaxing non-root and read-only-rootfs while keeping dropped capabilities. kurly authors no Secret; MATOMO_DATABASE_PASSWORD comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :80.',
      stages: {
        server: d.fn('The Matomo server. dbHost/dbName/dbUser point at a MySQL/MariaDB (e.g. mysql-cluster). secretName holds MATOMO_DATABASE_PASSWORD (envFrom). Config/plugins at /var/www/html. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='matomo'),
          d.arg('image', d.T.string, default='docker.io/library/matomo:5.12.0-apache'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='matomo-db'),
          d.arg('dbName', d.T.string, default='matomo'),
          d.arg('dbUser', d.T.string, default='matomo'),
          d.arg('secretName', d.T.string, default='matomo-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/matomo/server.libsonnet' },
      },
    },
    wikijs: {
      summary: 'A Wiki.js server (a modern, open-source wiki) on the official image, backed by an external PostgreSQL. Its content and configuration live in the database, so it is stateless and can run several replicas. Pairs with a cnpg-cluster named wikijs-db. kurly authors no Secret; DB_PASS comes from a provided Secret via envFrom. Serves on :3000.',
      stages: {
        server: d.fn('The Wiki.js server. dbHost/dbName/dbUser default to a cnpg-cluster named wikijs-db. secretName holds DB_PASS (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='wikijs'),
          d.arg('image', d.T.string, default='ghcr.io/requarks/wiki:2.5.314'),
          d.arg('dbHost', d.T.string, default='wikijs-db-rw'),
          d.arg('dbName', d.T.string, default='wikijs'),
          d.arg('dbUser', d.T.string, default='wikijs'),
          d.arg('secretName', d.T.string, default='wikijs-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/wikijs/server.libsonnet' },
      },
    },
    n8n: {
      summary: 'An n8n server (a fair-code workflow-automation tool with a visual editor) on the official image. A plain composable http workload that keeps its workflows, credentials, and encryption key in SQLite on a PersistentVolume by default — no external database. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves the editor, API, and webhooks on :5678.',
      stages: {
        server: d.fn('The n8n server. Keeps everything (SQLite + auto-generated encryption key) at /home/node/.n8n on the volume. host is the public hostname (webhooks need it). Point DB_TYPE at external PostgreSQL and set N8N_ENCRYPTION_KEY via env to scale out. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='n8n'),
          d.arg('image', d.T.string, default='docker.io/n8nio/n8n:2.31.4'),
          d.arg('storageSize', d.T.quantity, default='2Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('host', d.T.string, example='n8n.example.com'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/n8n/server.libsonnet' },
      },
    },
    ghost: {
      summary: 'A Ghost server (a modern publishing and newsletter platform) on the official image, backed by an external MySQL/MariaDB (the mysql-cluster workload provides one), with content on a PersistentVolume. kurly authors no Secret; the database password comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :2368.',
      stages: {
        server: d.fn('The Ghost server. dbHost/dbName/dbUser point at a MySQL/MariaDB (e.g. mysql-cluster). url is the public URL. secretName holds the DB password (envFrom). Content at /var/lib/ghost/content. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='ghost'),
          d.arg('image', d.T.string, default='docker.io/library/ghost:5.130.6-alpine'),
          d.arg('storageSize', d.T.quantity, default='5Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='ghost-db'),
          d.arg('dbName', d.T.string, default='ghost'),
          d.arg('dbUser', d.T.string, default='ghost'),
          d.arg('url', d.T.string, example='https://blog.example.com'),
          d.arg('secretName', d.T.string, default='ghost-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/ghost/server.libsonnet' },
      },
    },
    metabase: {
      summary: 'A Metabase server (an open-source business-intelligence and analytics tool) on the official image, backed by an external PostgreSQL for its application database. Its state lives in the database, so it is stateless and can run several replicas. Pairs with a cnpg-cluster named metabase-db. kurly authors no Secret; MB_DB_PASS comes from a provided Secret via envFrom. Serves on :3000.',
      stages: {
        server: d.fn('The Metabase server. dbHost/dbName/dbUser default to a cnpg-cluster named metabase-db (its application database). secretName holds MB_DB_PASS (envFrom). Scales horizontally via replicas. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='metabase'),
          d.arg('image', d.T.string, default='docker.io/metabase/metabase:v0.62.5'),
          d.arg('dbHost', d.T.string, default='metabase-db-rw'),
          d.arg('dbName', d.T.string, default='metabase'),
          d.arg('dbUser', d.T.string, default='metabase'),
          d.arg('secretName', d.T.string, default='metabase-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '300m', memory: '1Gi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/metabase/server.libsonnet' },
      },
    },
    directus: {
      summary: 'A Directus server (an open-source headless CMS and data platform over your SQL database) on the official image, backed by an external PostgreSQL, with uploads on a PersistentVolume. Pairs with a cnpg-cluster named directus-db. kurly authors no Secret; DB_PASSWORD, KEY, SECRET, and the admin password come from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves on :8055.',
      stages: {
        server: d.fn('The Directus server. dbHost/dbName/dbUser default to a cnpg-cluster named directus-db. publicUrl is the public URL; adminEmail the first-run admin. secretName holds DB_PASSWORD, KEY, SECRET, ADMIN_PASSWORD (envFrom). Uploads at /directus/uploads. Compose an exposure onto the HTTP port.', [
          d.arg('name', d.T.string, default='directus'),
          d.arg('image', d.T.string, default='docker.io/directus/directus:12.1.1'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('dbHost', d.T.string, default='directus-db-rw'),
          d.arg('dbName', d.T.string, default='directus'),
          d.arg('dbUser', d.T.string, default='directus'),
          d.arg('publicUrl', d.T.string, example='https://cms.example.com'),
          d.arg('adminEmail', d.T.string, default='admin@example.com'),
          d.arg('secretName', d.T.string, default='directus-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/directus/server.libsonnet' },
      },
    },
    ferretdb: {
      summary: 'A FerretDB server (an open-source, MongoDB-compatible database) — the Apache-2.0 alternative to MongoDB Community (SSPL) for a platform that monetizes hosting. A stateless proxy that speaks the MongoDB wire protocol and stores everything in a PostgreSQL backend (with the DocumentDB extension), so it needs no volume and can run several replicas. kurly authors no Secret; FERRETDB_POSTGRESQL_URL comes from a provided Secret via envFrom. Serves MongoDB wire on :27017.',
      stages: {
        server: d.fn('The FerretDB proxy. secretName holds FERRETDB_POSTGRESQL_URL (with the backend password, envFrom). The backend is a PostgreSQL with the DocumentDB extension — run one with cnpg-cluster pinned to imageName=ghcr.io/ferretdb/postgres-documentdb. Scales horizontally via replicas. Route :27017 as TCP for MongoDB clients.', [
          d.arg('name', d.T.string, default='ferretdb'),
          d.arg('image', d.T.string, default='ghcr.io/ferretdb/ferretdb:2.7.0'),
          d.arg('secretName', d.T.string, default='ferretdb-secrets'),
          d.arg('replicas', d.T.int, default=1),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet' },
      },
    },
    neo4j: {
      summary: 'A Neo4j graph database on the official Community image. Unlike the other database workloads, Neo4j Community has no operator and does not cluster (clustering is Enterprise), so this is a plain composable http single-instance workload rather than a CR — its graph lives on a PersistentVolume. Community Edition is GPLv3 (fine to run). kurly authors no Secret; NEO4J_AUTH comes from a provided Secret via envFrom. Single writer over a ReadWriteOnce volume: one replica, recreated. Serves HTTP on :7474 and Bolt on :7687.',
      stages: {
        server: d.fn('The Neo4j server. Graph at /data on the volume. secretName holds NEO4J_AUTH (neo4j/<password>, envFrom). Compose an exposure onto the HTTP port; route Bolt (:7687) as TCP. Clustering/HA needs Neo4j Enterprise, beyond this recipe.', [
          d.arg('name', d.T.string, default='neo4j'),
          d.arg('image', d.T.string, default='docker.io/library/neo4j:5.26.28-community'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='neo4j-secrets'),
          d.arg('env', d.T.object, default={}),
          d.arg('resources', d.T.object, default={ requests: { cpu: '200m', memory: '1Gi' }, limits: { memory: '2Gi' } }),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + { kind: 'http', importPath: 'github.com/metio/kurly/workloads/neo4j/server.libsonnet' },
      },
    },
    'cassandra-cluster': {
      summary: 'A highly-available Apache Cassandra cluster as a cass-operator CassandraDatacenter custom resource. Cassandra is Apache-2.0 — a clean default for a platform that monetizes hosting. Authors the CR directly like cnpg-cluster; composed by parameter, not by + feature. Requires cass-operator; the operator mints the superuser Secret.',
      stages: {
        cluster: d.fn('The CassandraDatacenter CR. name is the datacenter name; clusterName defaults to it. size is the node count. config is extra cassandra.yaml/JVM tuning (cass-operator schema, verbatim). Render with kurly.list.', [
          d.arg('name', d.T.string, default='cassandra'),
          d.arg('clusterName', d.T.string),
          d.arg('size', d.T.int, default=3),
          d.arg('serverVersion', d.T.string, default='4.1.7'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '1', memory: '2Gi' }, limits: { memory: '4Gi' } }),
          d.arg('config', d.T.object, default={}),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'cassandra',
          importPath: 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet',
        },
      },
    },
    'mongodb-cluster': {
      summary: 'A highly-available MongoDB replica set as a MongoDB Community Operator MongoDBCommunity custom resource. Authors the CR directly like cnpg-cluster; composed by parameter, not by + feature. Requires the MongoDB Community Operator and a consumer-provided admin-password Secret. WARNING: MongoDB Community Edition is SSPL-licensed (restricts offering it as a service) — the operator is Apache-2.0 but the server is not; prefer FerretDB (Apache-2.0) if SSPL is a problem for a monetized hosting platform.',
      stages: {
        cluster: d.fn('The MongoDBCommunity CR (a SCRAM-authenticated ReplicaSet). members are replica-set members (odd count for quorum). secretName is a Secret you provide with the admin password (key `password`); adminUser is created on bootstrap. Storage is set via the operator StatefulSet override. Render with kurly.list.', [
          d.arg('name', d.T.string, default='mongodb'),
          d.arg('members', d.T.int, default=3),
          d.arg('mongodbVersion', d.T.string, default='8.0.4'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('logsSize', d.T.quantity, default='2Gi'),
          d.arg('adminUser', d.T.string, default='admin'),
          d.arg('secretName', d.T.string, default='mongodb-admin'),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'mongodb',
          importPath: 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet',
        },
      },
    },
    'opensearch-cluster': {
      summary: 'A highly-available OpenSearch cluster as an OpenSearch Operator OpenSearchCluster custom resource, with optional OpenSearch Dashboards. OpenSearch is the Apache-2.0 fork of Elasticsearch — no SSPL/Elastic-License restriction on offering it as a service, the right default for a platform that monetizes hosting. Authors the CR directly like cnpg-cluster; composed by parameter, not by + feature. Requires the OpenSearch Operator.',
      stages: {
        cluster: d.fn('The OpenSearchCluster CR. replicas is the default node pool size (each node is cluster_manager+data+ingest; split into dedicated pools via the raw + hatch for large clusters). dashboards runs OpenSearch Dashboards alongside. Render with kurly.list.', [
          d.arg('name', d.T.string, default='opensearch'),
          d.arg('replicas', d.T.int, default=3),
          d.arg('opensearchVersion', d.T.string, default='2.19.1'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('resources', d.T.object, default={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } }),
          d.arg('dashboards', d.T.bool, default=true),
          d.arg('dashboardsReplicas', d.T.int, default=1),
          d.arg('labels', d.T.object, default={}),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'opensearch',
          importPath: 'github.com/metio/kurly/workloads/opensearch-cluster/cluster.libsonnet',
        },
      },
    },
    'mysql-cluster': {
      summary: 'A highly-available MySQL cluster as an Oracle MySQL Operator InnoDBCluster custom resource (Group Replication fronted by MySQL Router). The MySQL counterpart to cnpg-cluster — an app that needs MySQL/MariaDB instead of PostgreSQL points its dbHost at this cluster. Requires the MySQL Operator for Kubernetes; unlike CNPG, you provide the root-credentials Secret (kurly mints none).',
      stages: {
        cluster: d.fn('The MySQL InnoDBCluster CR. Adapt with the parameters and render with kurly.list — composed by parameter, not by + feature (it is a custom resource). secretName is a Secret you provide with rootUser/rootHost/rootPassword. instances are Group Replication members (odd count for quorum); routerInstances the routing tier.', [
          d.arg('name', d.T.string, default='mysql'),
          d.arg('instances', d.T.int, default=3),
          d.arg('routerInstances', d.T.int, default=2),
          d.arg('serverVersion', d.T.string, default='8.4.4'),
          d.arg('storageSize', d.T.quantity, default='10Gi'),
          d.arg('storageClass', d.T.string),
          d.arg('secretName', d.T.string, default='mysql-root'),
          d.arg('resources', d.T.object),
          d.arg('tlsUseSelfSigned', d.T.bool, default=true),
          d.arg('imagePullSecrets', d.T.array, default=[]),
          d.arg('labels', d.T.object, default={}, example={ team: 'payments' }),
          d.arg('annotations', d.T.object, default={}),
        ]) + {
          kind: 'mysql',
          importPath: 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet',
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
