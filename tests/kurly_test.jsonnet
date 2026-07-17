// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Assertion suite: every field evaluates to true (std.assertEqual raises on
// mismatch), so `jsonnet -J vendor tests/kurly_test.jsonnet` is the test run.
// Error paths (composing conflicting features) cannot be asserted here — jsonnet
// has no try/catch — so they live as negative checks in the CI test job.
local kurly = import '../main.libsonnet';

local shop = kurly.http('shop', 'ghcr.io/example/shop:1.2.3')
             + kurly.replicas(3)
             + kurly.labels({ team: 'storefront' })
             + kurly.env({ ZED: 'last' })
             + kurly.env({ ALPHA: 'first' })
             + kurly.probes('/health');

local ingressed = shop + kurly.expose.ingress('shop.example.com', ingressClass='nginx');

local routed = shop + kurly.expose.gateway('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure', sectionName='https');

local api = kurly.http('users', 'ghcr.io/example/users:2.0.0')
            + kurly.port(3000)
            + kurly.resources(limits={ memory: '256Mi' })
            + kurly.annotations({ 'example.com/scrape': 'true' });

local worker = kurly.worker('mailer', 'ghcr.io/example/mailer:1.0.0')
               + kurly.replicas(4)
               + kurly.serviceAccount('mailer');

local cron = kurly.cron('backup', 'ghcr.io/example/backup:1.0.0', '13 3 * * *')
             + kurly.serviceAccount('backup');

local daemon = kurly.daemon('node-agent', 'ghcr.io/example/agent:1.0.0');

// A stateful workload exercising the storage-and-mounts features.
local stateful = kurly.http('vault', 'ghcr.io/example/vault:1.0.0')
                 + kurly.replicas(1)
                 + kurly.recreate()
                 + kurly.runAs(12345)
                 + kurly.args(['server', '--config=/etc/vault/config.edn'])
                 + kurly.store('/var/lib/vault', '5Gi', storageClass='fast')
                 + kurly.config({ 'config.edn': '{:mode :append}' }, mountPath='/etc/vault')
                 + kurly.secretMount('vault-key', '/etc/vault-keys', optional=true, defaultMode=256)
                 + kurly.scratch('/tmp', '32Mi');

local containerOf(app) = app.deployment.spec.template.spec.containers[0];
local podOf(app) = app.deployment.spec.template.spec;

{
  // --- http ------------------------------------------------------------------
  http_replicas: std.assertEqual(shop.deployment.spec.replicas, 3),
  http_image: std.assertEqual(containerOf(shop).image, 'ghcr.io/example/shop:1.2.3'),

  // User labels land on metadata and the pod template, but never in the
  // immutable selector.
  http_selector_is_stable: std.assertEqual(
    shop.deployment.spec.selector.matchLabels,
    { name: 'shop', 'app.kubernetes.io/name': 'shop' }
  ),
  http_user_labels_on_metadata: std.assertEqual(shop.deployment.metadata.labels.team, 'storefront'),
  http_user_labels_on_pods: std.assertEqual(shop.deployment.spec.template.metadata.labels.team, 'storefront'),

  // The env map renders as a sorted array, so rendered output is deterministic
  // regardless of the order the kurly.env features added the variables.
  http_env_sorted: std.assertEqual(
    containerOf(shop).env,
    [{ name: 'ALPHA', value: 'first' }, { name: 'ZED', value: 'last' }]
  ),

  http_probes: std.assertEqual(
    containerOf(shop).readinessProbe.httpGet,
    { path: '/health', port: 'http' }
  ),

  http_service_targets_named_port: std.assertEqual(
    shop.service.spec.ports,
    [{ name: 'http', port: 80, targetPort: 'http' }]
  ),
  http_service_selector_matches_pods: std.assertEqual(
    shop.service.spec.selector,
    { 'app.kubernetes.io/name': 'shop' }
  ),

  http_port_override: std.assertEqual(
    containerOf(api).ports,
    [{ containerPort: 3000, name: 'http' }]
  ),

  // kurly.resources merges: adding limits keeps the default requests.
  http_limits_added: std.assertEqual(
    containerOf(api).resources,
    { requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } }
  ),

  http_annotations_on_metadata: std.assertEqual(api.deployment.metadata.annotations, { 'example.com/scrape': 'true' }),
  http_annotations_on_pods: std.assertEqual(
    api.deployment.spec.template.metadata.annotations,
    { 'example.com/scrape': 'true' }
  ),

  // A plain http workload carries no routing objects at all.
  http_no_ingress: std.assertEqual(std.objectHas(shop, 'ingress'), false),
  http_no_httproute: std.assertEqual(std.objectHas(shop, 'httproute'), false),

  // Features late-bind: an image swap composed after exposure still lands in
  // the rendered container, because features feed config, not manifests.
  late_binding: std.assertEqual(
    containerOf(routed + kurly.image('ghcr.io/example/shop:2.0.0')).image,
    'ghcr.io/example/shop:2.0.0'
  ),

  // --- args / command --------------------------------------------------------
  container_args: std.assertEqual(containerOf(stateful).args, ['server', '--config=/etc/vault/config.edn']),
  command_override: std.assertEqual(
    containerOf(shop + kurly.command(['/bin/app'])).command,
    ['/bin/app']
  ),

  // --- expose.ingress ----------------------------------------------------------
  ingress_host: std.assertEqual(ingressed.ingress.spec.rules[0].host, 'shop.example.com'),
  ingress_class: std.assertEqual(ingressed.ingress.spec.ingressClassName, 'nginx'),
  ingress_backend: std.assertEqual(
    ingressed.ingress.spec.rules[0].http.paths[0].backend.service,
    { name: 'shop', port: { name: 'http' } }
  ),
  ingress_labels: std.assertEqual(ingressed.ingress.metadata.labels.team, 'storefront'),

  // --- expose.gateway (reuse an existing Gateway) --------------------------------
  gateway_parent: std.assertEqual(
    routed.httproute.spec.parentRefs,
    [{ name: 'shared-gateway', namespace: 'infrastructure', sectionName: 'https' }]
  ),
  gateway_hostnames: std.assertEqual(routed.httproute.spec.hostnames, ['shop.example.com']),
  gateway_backend: std.assertEqual(
    routed.httproute.spec.rules[0].backendRefs,
    [{ name: 'shop', port: 80 }]
  ),
  gateway_no_ingress: std.assertEqual(std.objectHas(routed, 'ingress'), false),
  gateway_generates_no_gateway: std.assertEqual(std.objectHas(routed, 'gateway'), false),

  // Optional parentRef fields stay absent when not given.
  gateway_minimal_parent: std.assertEqual(
    (shop + kurly.expose.gateway('shop.example.com', 'shared')).httproute.spec.parentRefs,
    [{ name: 'shared' }]
  ),

  // --- expose.listenerSet (reuse an existing ListenerSet) ------------------------
  listenerset_parent: std.assertEqual(
    (shop + kurly.expose.listenerSet('shop.example.com', 'tenant-listeners', listenerSetNamespace='infrastructure')).httproute.spec.parentRefs,
    [{
      group: 'gateway.networking.k8s.io',
      kind: 'ListenerSet',
      name: 'tenant-listeners',
      namespace: 'infrastructure',
    }]
  ),

  // --- expose.ownGateway ---------------------------------------------------------
  own_gateway: std.assertEqual(
    (shop + kurly.expose.ownGateway('shop.example.com', 'cilium')).gateway.spec,
    {
      gatewayClassName: 'cilium',
      listeners: [{
        name: 'http',
        protocol: 'HTTP',
        port: 80,
        hostname: 'shop.example.com',
        allowedRoutes: { namespaces: { from: 'Same' } },
      }],
    }
  ),
  own_gateway_route_attaches: std.assertEqual(
    (shop + kurly.expose.ownGateway('shop.example.com', 'cilium')).httproute.spec.parentRefs,
    [{ name: 'shop' }]
  ),

  // --- expose.ownListenerSet -------------------------------------------------------
  own_listenerset_api: std.assertEqual(
    local ls = (shop + kurly.expose.ownListenerSet('shop.example.com', 'shared-gateway')).listenerset;
    [ls.apiVersion, ls.kind],
    ['gateway.networking.k8s.io/v1', 'ListenerSet']
  ),
  own_listenerset: std.assertEqual(
    (shop + kurly.expose.ownListenerSet('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure')).listenerset.spec,
    {
      parentRef: {
        group: 'gateway.networking.k8s.io',
        kind: 'Gateway',
        name: 'shared-gateway',
        namespace: 'infrastructure',
      },
      listeners: [{ name: 'http', protocol: 'HTTP', port: 80, hostname: 'shop.example.com' }],
    }
  ),
  own_listenerset_route_attaches: std.assertEqual(
    (shop + kurly.expose.ownListenerSet('shop.example.com', 'shared-gateway')).httproute.spec.parentRefs,
    [{ group: 'gateway.networking.k8s.io', kind: 'ListenerSet', name: 'shop' }]
  ),

  // Exactly one exposure composes; every recipe claims the `exposure` exclusion
  // group, so a single one renders its one routing object. (Composing two fails
  // the render — the negative check lives in the CI test job.)
  single_exposure_object_count: std.assertEqual(std.length(kurly.list(routed).items), 3),

  // --- worker ----------------------------------------------------------------
  worker_replicas: std.assertEqual(worker.deployment.spec.replicas, 4),
  worker_no_service: std.assertEqual(std.objectHas(worker, 'service'), false),
  worker_no_ports: std.assertEqual(std.objectHas(containerOf(worker), 'ports'), false),
  worker_service_account: std.assertEqual(podOf(worker).serviceAccountName, 'mailer'),

  // --- cron ------------------------------------------------------------------
  cron_schedule: std.assertEqual(cron.cronjob.spec.schedule, '13 3 * * *'),
  cron_forbids_overlap: std.assertEqual(cron.cronjob.spec.concurrencyPolicy, 'Forbid'),
  cron_restart_policy: std.assertEqual(
    cron.cronjob.spec.jobTemplate.spec.template.spec.restartPolicy,
    'OnFailure'
  ),
  cron_service_account: std.assertEqual(
    cron.cronjob.spec.jobTemplate.spec.template.spec.serviceAccountName,
    'backup'
  ),
  cron_reschedule: std.assertEqual((cron + kurly.schedule('0 4 * * *')).cronjob.spec.schedule, '0 4 * * *'),

  // --- daemon ----------------------------------------------------------------
  daemon_kind: std.assertEqual(daemon.daemonset.kind, 'DaemonSet'),
  daemon_selector: std.assertEqual(
    daemon.daemonset.spec.selector.matchLabels,
    { name: 'node-agent', 'app.kubernetes.io/name': 'node-agent' }
  ),

  // --- storage & mounts ------------------------------------------------------
  // kurly.store adds an owned PVC named <app>-store and mounts it.
  store_pvc: std.assertEqual(
    [stateful.storeClaim.kind, stateful.storeClaim.metadata.name, stateful.storeClaim.spec.resources.requests.storage, stateful.storeClaim.spec.storageClassName, stateful.storeClaim.spec.accessModes],
    ['PersistentVolumeClaim', 'vault-store', '5Gi', 'fast', ['ReadWriteOnce']]
  ),
  // kurly.config renders a ConfigMap named <app>-config.
  config_configmap: std.assertEqual(
    [stateful.configMap.kind, stateful.configMap.metadata.name, stateful.configMap.data['config.edn']],
    ['ConfigMap', 'vault-config', '{:mode :append}']
  ),
  // The owned manifests surface as a list and ride along in kurly.list
  // (Deployment + Service + PVC + ConfigMap = 4).
  owned_manifests: std.assertEqual(std.length(stateful.ownedManifests), 2),
  list_includes_owned: std.assertEqual(std.length(kurly.list(stateful).items), 4),
  // Every source contributes a paired (volume, mount) under one shared name.
  mount_names: std.assertEqual(
    [m.name for m in containerOf(stateful).volumeMounts],
    ['store', 'config', 'vault-key', 'tmp']
  ),
  volume_names: std.assertEqual([v.name for v in podOf(stateful).volumes], ['store', 'config', 'vault-key', 'tmp']),
  store_mount_path: std.assertEqual(
    [m.mountPath for m in containerOf(stateful).volumeMounts if m.name == 'store'][0],
    '/var/lib/vault'
  ),
  config_mount_readonly: std.assertEqual(
    [m.readOnly for m in containerOf(stateful).volumeMounts if m.name == 'config'][0],
    true
  ),
  secret_volume: std.assertEqual(
    local v = [v for v in podOf(stateful).volumes if v.name == 'vault-key'][0];
    [v.secret.secretName, v.secret.optional, v.secret.defaultMode],
    ['vault-key', true, 256]
  ),
  scratch_emptydir: std.assertEqual(
    [v.emptyDir.sizeLimit for v in podOf(stateful).volumes if v.name == 'tmp'][0],
    '32Mi'
  ),
  // kurly.runAs pins uid/gid on the container and fsGroup on the pod.
  user_and_fsgroup: std.assertEqual(
    [
      containerOf(stateful).securityContext.runAsUser,
      containerOf(stateful).securityContext.runAsGroup,
      podOf(stateful).securityContext.fsGroup,
      podOf(stateful).securityContext.fsGroupChangePolicy,
    ],
    [12345, 12345, 12345, 'OnRootMismatch']
  ),
  // kurly.recreate sets the Deployment strategy.
  recreate_strategy: std.assertEqual(stateful.deployment.spec.strategy.type, 'Recreate'),

  // --- scheduling & placement -------------------------------------------------
  // A bare workload carries no scheduling stanza at all.
  scheduling_absent_by_default: std.assertEqual(
    [std.objectHas(podOf(shop), f) for f in ['nodeSelector', 'tolerations', 'topologySpreadConstraints', 'affinity']],
    [false, false, false, false]
  ),
  // resourcePreset replaces the container resources with the named size.
  resource_preset: std.assertEqual(
    (shop + kurly.resourcePreset('small')).deployment.spec.template.spec.containers[0].resources,
    { requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '256Mi' } }
  ),
  // The placement features land on the pod template verbatim.
  node_selector: std.assertEqual(podOf(shop + kurly.nodeSelector({ disktype: 'ssd' })).nodeSelector, { disktype: 'ssd' }),
  tolerations_set: std.assertEqual(
    std.length(podOf(shop + kurly.tolerations([{ key: 'gpu', operator: 'Exists' }])).tolerations), 1
  ),
  topology_spread_set: std.assertEqual(
    podOf(shop + kurly.topologySpread([{ maxSkew: 1, topologyKey: 'kubernetes.io/hostname', whenUnsatisfiable: 'DoNotSchedule' }])).topologySpreadConstraints[0].maxSkew, 1
  ),
  affinity_set: std.assertEqual(
    std.objectHas(podOf(shop + kurly.affinity({ nodeAffinity: {} })), 'affinity'), true
  ),
  // Scheduling composes onto the CronJob pod template too, not just Deployments.
  cron_node_selector: std.assertEqual(
    (cron + kurly.nodeSelector({ disktype: 'ssd' })).cronjob.spec.jobTemplate.spec.template.spec.nodeSelector, { disktype: 'ssd' }
  ),

  // --- pod-template extras & owned manifests ---------------------------------
  // podLabels reach the pod template but never the immutable selector.
  pod_labels_scoped: std.assertEqual(
    local a = shop + kurly.podLabels({ tier: 'db' });
    [a.deployment.spec.template.metadata.labels.tier, std.objectHas(a.deployment.spec.selector.matchLabels, 'tier')],
    ['db', false]
  ),
  // podAnnotations land on the pod template only, not the workload metadata.
  pod_annotations_scoped: std.assertEqual(
    local a = shop + kurly.podAnnotations({ 'linkerd.io/inject': 'enabled' });
    [
      a.deployment.spec.template.metadata.annotations['linkerd.io/inject'],
      std.objectHas(a.deployment.metadata, 'annotations'),
    ],
    ['enabled', false]
  ),
  // imagePullSecrets and priorityClassName reach the pod spec.
  pod_spec_extras: std.assertEqual(
    local a = shop + kurly.imagePullSecrets(['regcred']) + kurly.priorityClassName('high');
    [podOf(a).imagePullSecrets, podOf(a).priorityClassName],
    [[{ name: 'regcred' }], 'high']
  ),
  // Owned manifests select the workload's own pods and ride along in list().
  pdb_selects_workload: std.assertEqual(
    (shop + kurly.pdb(minAvailable=1)).pdb.spec,
    { selector: { matchLabels: { 'app.kubernetes.io/name': 'shop' } }, minAvailable: 1 }
  ),
  hpa_targets_deployment: std.assertEqual(
    local h = (shop + kurly.hpa(2, 10, targetCPU=80)).hpa.spec;
    [h.scaleTargetRef.kind, h.scaleTargetRef.name, h.minReplicas, h.maxReplicas, h.metrics[0].resource.target.averageUtilization],
    ['Deployment', 'shop', 2, 10, 80]
  ),
  owned_manifests_ride_along: std.assertEqual(
    std.length(kurly.list(shop + kurly.pdb(maxUnavailable=1) + kurly.serviceMonitor() + kurly.networkPolicy(policyTypes=['Ingress'])).items),
    5  // Deployment + Service + PDB + ServiceMonitor + NetworkPolicy
  ),
  // rbac mints SA + Role + RoleBinding and runs the pod under that SA.
  rbac_mints_and_wires: std.assertEqual(
    local a = kurly.worker('agent', 'ghcr.io/example/agent:1.0.0') + kurly.rbac([{ apiGroups: [''], resources: ['pods'], verbs: ['get'] }]);
    [
      std.sort([m.kind for m in kurly.list(a).items]),
      podOf(a).serviceAccountName,
    ],
    [['Deployment', 'Role', 'RoleBinding', 'ServiceAccount'], 'agent']
  ),

  // apiServerClient mints the RBAC (SA + Role + RoleBinding) and runs the pod
  // under it even without an explicit rbac(), the Role carrying the declared rules.
  api_server_client_mints_rbac: std.assertEqual(
    local a = kurly.worker('agent', 'ghcr.io/example/agent:1.0.0')
              + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }]);
    local role = [m for m in kurly.list(a).items if m.kind == 'Role'][0];
    [std.sort([m.kind for m in kurly.list(a).items]), podOf(a).serviceAccountName, role.rules],
    [
      ['Deployment', 'Role', 'RoleBinding', 'ServiceAccount'],
      'agent',
      [{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }],
    ]
  ),
  // A consumer's own rbac() and a capability's requiredRbac union into one Role —
  // neither clobbers the other, regardless of compose order.
  required_rbac_unions_with_rbac: std.assertEqual(
    local a = kurly.worker('agent', 'ghcr.io/example/agent:1.0.0')
              + kurly.rbac([{ apiGroups: [''], resources: ['configmaps'], verbs: ['get'] }])
              + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }]);
    [m for m in kurly.list(a).items if m.kind == 'Role'][0].rules,
    [
      { apiGroups: [''], resources: ['configmaps'], verbs: ['get'] },
      { apiGroups: [''], resources: ['pods'], verbs: ['patch'] },
    ]
  ),
  // requiredEgress a capability declared is always allowed by a consumer's
  // NetworkPolicy, and Egress joins an ingress-only policyTypes so it takes effect.
  required_egress_survives_network_policy: std.assertEqual(
    local a = kurly.worker('agent', 'ghcr.io/example/agent:1.0.0')
              + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }])
              + kurly.networkPolicy(ingress=[{ from: [{ podSelector: {} }] }], policyTypes=['Ingress']);
    local np = [m for m in kurly.list(a).items if m.kind == 'NetworkPolicy'][0].spec;
    [np.policyTypes, np.egress],
    [['Ingress', 'Egress'], [{ ports: [{ protocol: 'TCP', port: 443 }, { protocol: 'TCP', port: 6443 }] }]]
  ),
  // Without a NetworkPolicy, requiredEgress mints nothing — egress is allow-all,
  // so the requirement is moot and no policy object appears.
  required_egress_mints_no_policy_alone: std.assertEqual(
    local a = kurly.worker('agent', 'ghcr.io/example/agent:1.0.0')
              + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }]);
    std.length([m for m in kurly.list(a).items if m.kind == 'NetworkPolicy']),
    0
  ),

  // --- stateful & job kinds ---------------------------------------------------
  // stateful emits a StatefulSet + a headless Service naming it; the store
  // becomes a per-pod volumeClaimTemplate, not a shared owned PVC.
  stateful_shape: std.assertEqual(
    local s = kurly.stateful('db', 'ghcr.io/example/db:16') + kurly.replicas(3) + kurly.store('/var/lib/db', '5Gi');
    [
      std.sort([m.kind for m in kurly.list(s).items]),
      s.statefulset.spec.serviceName,
      s.service.spec.clusterIP,
      s.statefulset.spec.volumeClaimTemplates[0].spec.resources.requests.storage,
      s.storeClaim,  // no separate owned PVC
      s.statefulset.spec.replicas,
    ],
    [['Service', 'StatefulSet'], 'db-headless', 'None', '5Gi', null, 3]
  ),
  // The store still mounts at its path, sourced from the template's 'store' volume.
  stateful_store_mount: std.assertEqual(
    local s = kurly.stateful('db', 'ghcr.io/example/db:16') + kurly.store('/var/lib/db', '5Gi');
    [m.mountPath for m in s.statefulset.spec.template.spec.containers[0].volumeMounts if m.name == 'store'],
    ['/var/lib/db']
  ),
  // job runs to completion (restartPolicy OnFailure), no Service; store is a
  // shared PVC as on the other pod kinds.
  job_shape: std.assertEqual(
    local j = kurly.job('migrate', 'ghcr.io/example/migrate:1.0.0') + kurly.store('/scratch', '1Gi');
    [
      std.sort([m.kind for m in kurly.list(j).items]),
      j.job.spec.template.spec.restartPolicy,
      [v.persistentVolumeClaim.claimName for v in j.job.spec.template.spec.volumes if v.name == 'store'],
    ],
    [['Job', 'PersistentVolumeClaim'], 'OnFailure', ['migrate-store']]
  ),
  // The hardened posture applies to the new kinds too.
  stateful_restricted: std.assertEqual(
    (kurly.stateful('db', 'ghcr.io/example/db:16')).statefulset.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem,
    true
  ),
  job_restricted: std.assertEqual(
    (kurly.job('m', 'ghcr.io/example/m:1.0.0')).job.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem,
    true
  ),
  // A stateless workload is untouched: no owned manifests, no volumes.
  stateless_no_owned: std.assertEqual([std.length(shop.ownedManifests), shop.storeClaim, std.objectHas(podOf(shop), 'volumes')], [0, null, false]),
  stateless_list_unchanged: std.assertEqual(std.length(kurly.list(shop).items), 2),
  // Mounts work on the CronJob pod template too, not just Deployments.
  cron_mounts: std.assertEqual(
    [v.name for v in (cron + kurly.scratch('/work')).cronjob.spec.jobTemplate.spec.template.spec.volumes],
    ['work']
  ),

  // --- list ------------------------------------------------------------------
  list_kind: std.assertEqual(kurly.list(ingressed).kind, 'List'),
  list_renders_all_manifests: std.assertEqual(std.length(kurly.list(ingressed).items), 3),
  list_worker_has_only_deployment: std.assertEqual(std.length(kurly.list(worker).items), 1),
  // listOf renders explicit items and drops nulls (an absent owned manifest).
  list_of_drops_nulls: std.assertEqual(std.length(kurly.listOf([shop.deployment, shop.storeClaim, shop.service]).items), 2),
  // join drops nulls and flattens nested arrays one level.
  join_flattens_and_drops: std.assertEqual(kurly.join([1, null, [2, 3], 4]), [1, 2, 3, 4]),
  // An `if` with no else is null when false, so an unmet condition drops out.
  join_conditionals: std.assertEqual(kurly.join([1, if false then 2, if true then 3]), [1, 3]),
  // listOf accepts the same shape: conditionals and nested arrays of manifests.
  list_of_flattens_conditionals: std.assertEqual(
    std.length(kurly.listOf([shop.deployment, if false then shop.service, [shop.service, shop.storeClaim]]).items),
    2
  ),

  // --- Pod Security Standards (restricted) ------------------------------------
  // Every kind ships the full restricted profile by default.
  pss_pod_security_context: std.assertEqual(
    podOf(shop).securityContext,
    { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } }
  ),
  pss_user_namespace: std.assertEqual(podOf(shop).hostUsers, false),
  pss_container_hardening: std.assertEqual(
    containerOf(shop).securityContext,
    {
      allowPrivilegeEscalation: false,
      readOnlyRootFilesystem: true,
      capabilities: { drop: ['ALL'] },
    }
  ),
  pss_cron_pod_security: std.assertEqual(
    cron.cronjob.spec.jobTemplate.spec.template.spec.securityContext.runAsNonRoot,
    true
  ),
  pss_cron_user_namespace: std.assertEqual(
    cron.cronjob.spec.jobTemplate.spec.template.spec.hostUsers,
    false
  ),
  pss_daemon_pod_security: std.assertEqual(
    daemon.daemonset.spec.template.spec.securityContext.seccompProfile.type,
    'RuntimeDefault'
  ),

  // The ServiceAccount token is mounted only when a ServiceAccount is
  // explicitly configured.
  pss_no_token_by_default: std.assertEqual(podOf(shop).automountServiceAccountToken, false),
  pss_token_with_service_account: std.assertEqual(podOf(worker).automountServiceAccountToken, true),

  // Escape-hatch features downgrade exactly one default and leave the rest
  // intact. A relaxed knob omits its field rather than writing the k8s default.
  hatch_root_user: std.assertEqual(
    podOf(shop + kurly.rootUser()).securityContext,
    { seccompProfile: { type: 'RuntimeDefault' } }
  ),
  hatch_writable_root_filesystem: std.assertEqual(
    std.objectHas(containerOf(shop + kurly.writableRootFilesystem()).securityContext, 'readOnlyRootFilesystem'),
    false
  ),
  hatch_host_users: std.assertEqual(
    std.objectHas(podOf(shop + kurly.hostUsers()), 'hostUsers'),
    false
  ),
  hatch_host_users_keeps_profile: std.assertEqual(
    podOf(shop + kurly.hostUsers()).securityContext.runAsNonRoot,
    true
  ),

  // --- security profiles -------------------------------------------------------
  // Profiles compose with `+` like exposures; each sets every security knob,
  // so the last profile wins and hatches still fine-tune afterwards.

  // Explicitly composing the default is a no-op.
  security_restricted_is_default: std.assertEqual(
    (shop + kurly.security.restricted).deployment.spec.template.spec,
    podOf(shop)
  ),

  // baseline drops only what `restricted` requires beyond baseline — the pod
  // securityContext empties out entirely...
  security_baseline_pod: std.assertEqual(
    std.objectHas((shop + kurly.security.baseline).deployment.spec.template.spec, 'securityContext'),
    false
  ),
  // ...while kurly's extra hardening (read-only rootfs, user namespaces),
  // legal at every PSS level, stays on.
  security_baseline_keeps_extras: std.assertEqual(
    local spec = (shop + kurly.security.baseline).deployment.spec.template.spec;
    [spec.containers[0].securityContext, spec.hostUsers],
    [{ readOnlyRootFilesystem: true }, false]
  ),

  // privileged constrains nothing: no security fields anywhere. The token
  // automount rule is ServiceAccount hygiene, not PSS, so it stays.
  security_privileged: std.assertEqual(
    local spec = (shop + kurly.security.privileged).deployment.spec.template.spec;
    [
      std.objectHas(spec, 'securityContext'),
      std.objectHas(spec, 'hostUsers'),
      std.objectHas(spec.containers[0], 'securityContext'),
      spec.automountServiceAccountToken,
    ],
    [false, false, false, false]
  ),

  // The last-composed profile wins — restricted after baseline re-tightens.
  security_retighten: std.assertEqual(
    (shop + kurly.security.baseline + kurly.security.restricted).deployment.spec.template.spec.securityContext,
    { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } }
  ),

  // Hatch features fine-tune after a profile: baseline plus host user namespaces.
  security_profile_then_hatch: std.assertEqual(
    local spec = (shop + kurly.security.baseline + kurly.hostUsers()).deployment.spec.template.spec;
    [std.objectHas(spec, 'hostUsers'), spec.containers[0].securityContext.readOnlyRootFilesystem],
    [false, true]
  ),

  // Profiles work on every kind, not just Deployments.
  security_baseline_on_cron: std.assertEqual(
    std.objectHas((cron + kurly.security.baseline).cronjob.spec.jobTemplate.spec.template.spec, 'securityContext'),
    false
  ),

  // --- migrations ------------------------------------------------------------------
  // The serialized Migration carries only what was given — optional fields
  // and an empty action list are pruned, so the wire shape stays minimal.
  migration_minimal: std.assertEqual(
    kurly.migrations.migration('recreate', to='2.0.0'),
    { name: 'recreate', to: '2.0.0' }
  ),
  migration_full: std.assertEqual(
    kurly.migrations.migration('backfill', to='2.1.0', from='>=2.0.0', stage='production', actions=[
      { name: 'run', job: { sourceRef: { kind: 'ExternalArtifact', name: 'jobs' } } },
    ]),
    {
      name: 'backfill',
      to: '2.1.0',
      from: '>=2.0.0',
      stage: 'production',
      actions: [{ name: 'run', job: { sourceRef: { kind: 'ExternalArtifact', name: 'jobs' } } }],
    }
  ),
  // A ladder is a plain array — order is authoring order.
  migration_ladder_is_array: std.assertEqual(
    std.map(
      function(m) m.name,
      [kurly.migrations.migration('a', to='1.1.0'), kurly.migrations.migration('b', to='2.0.0')]
    ),
    ['a', 'b']
  ),
  // mirror rewrites the registry of every image in RENDERED manifests — the
  // reason it works on the output rather than the config is that an
  // initContainer's spec is passed through verbatim and a sidecar can be
  // grafted on with the raw + escape hatch, so config never sees either.
  mirror_rewrites_every_container: std.assertEqual(
    local rendered = kurly.mirror('harbor.internal/dockerhub', kurly.list(
      kurly.worker('app', 'docker.io/library/busybox:1.37.0')
      + kurly.initContainer({ name: 'init', image: 'ghcr.io/acme/init:1.0' })
      + { deployment+: { spec+: { template+: { spec+: { containers+: [
        { name: 'sidecar', image: 'quay.io/acme/sidecar:2.0' },
      ] } } } } }
    ));
    local pod = rendered.items[0].spec.template.spec;
    [pod.initContainers[0].image, pod.containers[0].image, pod.containers[1].image],
    [
      'harbor.internal/dockerhub/acme/init:1.0',
      'harbor.internal/dockerhub/library/busybox:1.37.0',
      'harbor.internal/dockerhub/acme/sidecar:2.0',
    ]
  ),
  // Only the registry moves: repository, tag and digest are carried through.
  mirror_keeps_repository_tag_and_digest: std.assertEqual(
    kurly.mirror('r.internal', { a: { image: 'ghcr.io/acme/app@sha256:abc' }, b: { imageName: 'docker.io/library/pg:17.2' } }),
    { a: { image: 'r.internal/acme/app@sha256:abc' }, b: { imageName: 'r.internal/library/pg:17.2' } }
  ),
  // A reference carrying no registry has nothing to replace, so it is left as
  // it is rather than guessed at.
  mirror_leaves_a_registryless_reference_alone: std.assertEqual(
    kurly.mirror('r.internal', { image: 'busybox:1.37.0' }),
    { image: 'busybox:1.37.0' }
  ),
  // A ConfigMap's payload is the application's data, not the kubelet's: a key
  // called image in there must survive untouched.
  mirror_does_not_touch_configmap_data: std.assertEqual(
    kurly.mirror('r.internal', { kind: 'ConfigMap', data: { image: 'docker.io/team/ref:1.0' } }),
    { kind: 'ConfigMap', data: { image: 'docker.io/team/ref:1.0' } }
  ),
  // A CNPG Cluster carries its own pull secrets: the operator pulls PostgreSQL,
  // so there is no pod for kurly.imagePullSecrets() to attach to.
  cnpg_cluster_takes_pull_secrets: std.assertEqual(
    (import '../workloads/cnpg-cluster/cluster.libsonnet')(
      imagePullSecrets=['regcred', 'other']
    ).cluster.spec.imagePullSecrets,
    [{ name: 'regcred' }, { name: 'other' }]
  ),
  // Unset, the field is pruned rather than emitted empty.
  cnpg_cluster_prunes_absent_pull_secrets: std.assertEqual(
    std.objectHas(
      (import '../workloads/cnpg-cluster/cluster.libsonnet')().cluster.spec,
      'imagePullSecrets'
    ),
    false
  ),
  // Dragonfly counts the cores it can SEE, which in a container is the node's,
  // so the thread count is always pinned rather than left to it.
  dragonfly_pins_its_thread_count: std.assertEqual(
    local args = (import '../workloads/dragonfly/instance.libsonnet')(threads=4, maxMemoryMB=1024).statefulset
                 .spec.template.spec.containers[0].args;
    args[std.find('--proactor_threads', args)[0] + 1],
    '4'
  ),
  // Dragonfly's own floor: below 256MiB per io thread it exits at startup, so
  // the CPU follows the thread count and the memory is checked before apply.
  dragonfly_sizes_cpu_from_threads: std.assertEqual(
    (import '../workloads/dragonfly/instance.libsonnet')(threads=4, maxMemoryMB=1024).statefulset
    .spec.template.spec.containers[0].resources.requests.cpu,
    '4'
  ),
  // It speaks RESP, not Redis's command line: --appendonly is an unknown flag
  // and an unknown flag is fatal, so the recipe must never emit one.
  dragonfly_emits_no_redis_flags: std.assertEqual(
    std.length(std.find('--appendonly',
                        (import '../workloads/dragonfly/instance.libsonnet')().statefulset
                        .spec.template.spec.containers[0].args)),
    0
  ),
}
