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
  // envFrom sources compose in order and carry an optional prefix; kurly mints
  // no Secret or ConfigMap — they are the consumer's to provide.
  env_from_secret_and_configmap: std.assertEqual(
    containerOf(shop + kurly.envFromSecret('creds') + kurly.envFromConfigMap('cfg', prefix='APP_')).envFrom,
    [{ secretRef: { name: 'creds' } }, { configMapRef: { name: 'cfg' }, prefix: 'APP_' }]
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
  single_exposure_object_count: std.assertEqual(std.length(kurly.list(routed).items), 4),

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
  // (Deployment + Service + PVC + ConfigMap + ServiceAccount = 5).
  owned_manifests: std.assertEqual(std.length(stateful.ownedManifests), 3),
  list_includes_owned: std.assertEqual(std.length(kurly.list(stateful).items), 5),
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
    6  // Deployment + Service + PDB + ServiceMonitor + NetworkPolicy + ServiceAccount
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
    [['Service', 'ServiceAccount', 'StatefulSet'], 'db-headless', 'None', '5Gi', null, 3]
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
    [['Job', 'PersistentVolumeClaim', 'ServiceAccount'], 'OnFailure', ['migrate-store']]
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
  // A stateless workload owns only its ServiceAccount (every workload runs under
  // a dedicated one) — no storage or config, no volumes.
  stateless_no_owned: std.assertEqual([std.length(shop.ownedManifests), shop.storeClaim, std.objectHas(podOf(shop), 'volumes')], [1, null, false]),
  stateless_list_unchanged: std.assertEqual(std.length(kurly.list(shop).items), 3),
  // Mounts work on the CronJob pod template too, not just Deployments.
  cron_mounts: std.assertEqual(
    [v.name for v in (cron + kurly.scratch('/work')).cronjob.spec.jobTemplate.spec.template.spec.volumes],
    ['work']
  ),

  // --- list ------------------------------------------------------------------
  list_kind: std.assertEqual(kurly.list(ingressed).kind, 'List'),
  list_renders_all_manifests: std.assertEqual(std.length(kurly.list(ingressed).items), 4),
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
  // A CR workload has no pod template, so kurly.podLabels() composed onto it
  // lands in a config nothing reads and vanishes WITHOUT error. CNPG's own
  // inheritedMetadata is the way through: the operator copies it onto every
  // object it generates, pods included.
  cnpg_cluster_pod_metadata_reaches_the_pods: std.assertEqual(
    (import '../workloads/cnpg-cluster/cluster.libsonnet')(
      labels={ team: 'payments' },
      annotations={ 'linkerd.io/inject': 'enabled' },
    ).cluster.spec.inheritedMetadata,
    { labels: { team: 'payments' }, annotations: { 'linkerd.io/inject': 'enabled' } }
  ),
  // They land on the Cluster itself too, merged over kurly's own identity
  // labels rather than replacing them.
  cnpg_cluster_labels_merge_with_kurlys: std.assertEqual(
    (import '../workloads/cnpg-cluster/cluster.libsonnet')(labels={ team: 'payments' })
    .cluster.metadata.labels,
    {
      'app.kubernetes.io/name': 'postgres',
      'app.kubernetes.io/managed-by': 'kurly',
      'app.kubernetes.io/version': 'dev',
      team: 'payments',
    }
  ),
  // Unset, neither field is emitted empty.
  cnpg_cluster_prunes_absent_pod_metadata: std.assertEqual(
    local spec = (import '../workloads/cnpg-cluster/cluster.libsonnet')().cluster;
    [std.objectHas(spec.spec, 'inheritedMetadata'), std.objectHas(spec.metadata, 'annotations')],
    [false, false]
  ),
  // A catalog generates no pods, so its metadata is its own.
  cnpg_catalog_takes_labels_and_annotations: std.assertEqual(
    local m = (import '../workloads/cnpg-image-catalog/namespaced.libsonnet')(
      labels={ team: 'payments' }, annotations={ a: 'b' }
    ).catalog.metadata;
    [m.labels.team, m.annotations.a],
    ['payments', 'b']
  ),
  // A uid written as a literal into a sidecar or an initContainer is beyond the
  // reach of kurly.runAs() and the security profiles — and on a cluster that
  // ASSIGNS uids (OpenShift gives each namespace a range and rejects anything
  // else) one stray literal strands the whole pod.
  sidecars_and_init_containers_follow_the_composed_uid: std.assertEqual(
    local a = kurly.worker('w', 'img:1')
              + kurly.initContainer({ name: 'init', image: 'img:1' })
              + kurly.sidecar({ name: 'agent', image: 'img:1' })
              + kurly.runAs(1000700000);
    local pod = a.deployment.spec.template.spec;
    [
      pod.initContainers[0].securityContext.runAsUser,
      pod.containers[0].securityContext.runAsUser,
      pod.containers[1].securityContext.runAsUser,
    ],
    [1000700000, 1000700000, 1000700000]
  ),
  // A sidecar that means it can still say so; its own securityContext wins.
  a_sidecar_may_override_the_posture: std.assertEqual(
    (kurly.worker('w', 'img:1')
     + kurly.sidecar({ name: 'agent', image: 'img:1', securityContext: { runAsUser: 4242 } })
     + kurly.runAs(1000700000)).deployment.spec.template.spec.containers[1].securityContext.runAsUser,
    4242
  ),
  // security.privileged emits no security fields at all, so no container carries
  // a securityContext — the sidecar must not resurrect one.
  privileged_leaves_sidecars_bare: std.assertEqual(
    std.objectHas(
      (kurly.worker('w', 'img:1') + kurly.sidecar({ name: 'agent', image: 'img:1' }) + kurly.security.privileged)
      .deployment.spec.template.spec.containers[1],
      'securityContext'
    ),
    false
  ),
  // Composing a feature onto a custom-resource workload cannot work: features
  // write a hidden config that a BASE KIND reads, and there is no base here. It
  // used to render cleanly and drop the labels — a green render and a cluster
  // that behaves differently from the source. Now it fails, and the raw `+`
  // escape hatch (which touches no config) still patches the resource.
  cnpg_cluster_takes_the_raw_escape_hatch: std.assertEqual(
    ((import '../workloads/cnpg-cluster/cluster.libsonnet')()
     + { cluster+: { spec+: { nodeMaintenanceWindow: { inProgress: false } } } })
    .cluster.spec.nodeMaintenanceWindow,
    { inProgress: false }
  ),
  // A consumer's ServiceAccount wins over the one a workload's RBAC would mint.
  // They are usually bringing an account annotated for cloud workload identity,
  // which kurly cannot know about — and a grant bound to some other account
  // would leave the pod without the rules the workload needs.
  an_explicit_service_account_wins_over_rbac: std.assertEqual(
    local a = kurly.worker('w', 'img:1')
              + kurly.rbac([{ apiGroups: [''], resources: ['pods'], verbs: ['get'] }])
              + kurly.serviceAccount('my-irsa-sa');
    local binding = [m for m in a.ownedManifests if m.kind == 'RoleBinding'][0];
    [
      a.deployment.spec.template.spec.serviceAccountName,
      binding.subjects[0].name,
      // kurly mints none: the account is the consumer's to own.
      std.length([m for m in a.ownedManifests if m.kind == 'ServiceAccount']),
    ],
    ['my-irsa-sa', 'my-irsa-sa', 0]
  ),
  // Without one, kurly still mints an account named after the workload, and it
  // can carry the annotation cloud workload identity is wired through.
  a_minted_service_account_takes_annotations: std.assertEqual(
    local a = kurly.worker('w', 'img:1')
              + kurly.rbac([{ apiGroups: [''], resources: ['pods'], verbs: ['get'] }])
              + kurly.serviceAccountAnnotations({ 'eks.amazonaws.com/role-arn': 'arn:aws:iam::1:role/w' });
    local sa = [m for m in a.ownedManifests if m.kind == 'ServiceAccount'][0];
    [sa.metadata.name, sa.metadata.annotations['eks.amazonaws.com/role-arn']],
    ['w', 'arn:aws:iam::1:role/w']
  ),
  // The token is mounted for whichever account the pod ends up running under.
  an_explicit_service_account_still_mounts_its_token: std.assertEqual(
    (kurly.worker('w', 'img:1') + kurly.serviceAccount('mine'))
    .deployment.spec.template.spec.automountServiceAccountToken,
    true
  ),
  // Which sandbox classes exist is the cluster's business, so it is set and
  // absent-by-default like the priority class beside it.
  runtime_class_reaches_the_pod_spec: std.assertEqual(
    local a = kurly.worker('w', 'img:1') + kurly.runtimeClassName('gvisor');
    [
      a.deployment.spec.template.spec.runtimeClassName,
      std.objectHas(kurly.worker('w', 'img:1').deployment.spec.template.spec, 'runtimeClassName'),
    ],
    ['gvisor', false]
  ),
  // Placement reaches a CNPG Cluster verbatim: `affinity` is CNPG's own schema,
  // not Kubernetes', so kurly passes it through rather than modelling a foreign
  // API it would only drift against.
  cnpg_cluster_takes_placement_verbatim: std.assertEqual(
    (import '../workloads/cnpg-cluster/cluster.libsonnet')(
      affinity={ nodeSelector: { workload: 'database' }, podAntiAffinityType: 'required' },
      priorityClassName='database-critical',
      topologySpreadConstraints=[{ maxSkew: 1, topologyKey: 'topology.kubernetes.io/zone', whenUnsatisfiable: 'DoNotSchedule' }],
      schedulerName='custom',
    ).cluster.spec,
    (import '../workloads/cnpg-cluster/cluster.libsonnet')().cluster.spec {
      affinity: { nodeSelector: { workload: 'database' }, podAntiAffinityType: 'required' },
      priorityClassName: 'database-critical',
      topologySpreadConstraints: [{ maxSkew: 1, topologyKey: 'topology.kubernetes.io/zone', whenUnsatisfiable: 'DoNotSchedule' }],
      schedulerName: 'custom',
    }
  ),
  // Unset, none of it is emitted.
  cnpg_cluster_prunes_absent_placement: std.assertEqual(
    local spec = (import '../workloads/cnpg-cluster/cluster.libsonnet')().cluster.spec;
    [f for f in ['affinity', 'topologySpreadConstraints', 'priorityClassName', 'schedulerName'] if std.objectHas(spec, f)],
    []
  ),
  // Several CSI drivers take their configuration through PVC annotations and
  // nothing else, so a dropped annotation provisions a DIFFERENT volume rather
  // than the same one with less decoration. The stateful path used to stop them
  // at the volumeClaimTemplate while the Deployment path carried them through.
  store_annotations_reach_a_volume_claim_template: std.assertEqual(
    (kurly.stateful('s', 'img:1') + kurly.store('/data', '5Gi', annotations={ 'ebs.csi.aws.com/iops': '3000' }))
    .statefulset.spec.volumeClaimTemplates[0].metadata,
    { name: 'store', annotations: { 'ebs.csi.aws.com/iops': '3000' } }
  ),
  // A volumeClaimTemplate is immutable, so a store with no annotations must
  // render exactly as before or every stateful workload already running would
  // fail its next apply.
  a_plain_volume_claim_template_is_unchanged: std.assertEqual(
    (kurly.stateful('s', 'img:1') + kurly.store('/data', '5Gi'))
    .statefulset.spec.volumeClaimTemplates[0].metadata,
    { name: 'store' }
  ),
  // Kubernetes keys a pod's volumes by name and a container's mounts by path, so
  // re-declaring one the workload already has must override it — not collide
  // with it, which the apiserver rejects outright and no consumer can work
  // around short of forking the recipe.
  re_declaring_a_scratch_overrides_it: std.assertEqual(
    local pod = (kurly.worker('w', 'img:1') + kurly.scratch('/gen', '64Mi') + kurly.scratch('/gen', '256Mi'))
                .deployment.spec.template.spec;
    [std.length(pod.volumes), pod.volumes[0].emptyDir.sizeLimit, std.length(pod.containers[0].volumeMounts)],
    [1, '256Mi', 1]
  ),
  // One Secret at two paths is one volume and two mounts — the additive case the
  // dedupe must not eat.
  one_secret_at_two_paths_is_one_volume: std.assertEqual(
    local pod = (kurly.worker('w', 'img:1') + kurly.secretMount('s', '/a') + kurly.secretMount('s', '/b'))
                .deployment.spec.template.spec;
    [[v.name for v in pod.volumes], [m.mountPath for m in pod.containers[0].volumeMounts]],
    [['s'], ['/a', '/b']]
  ),
  // A cloud load balancer is configured through Service annotations and nothing
  // else, and the keys differ per provider — kurly cannot know them, so a
  // Service that cannot carry them cannot be a working LoadBalancer anywhere.
  service_takes_a_type_and_annotations: std.assertEqual(
    local svc = (kurly.http('web', 'img:1')
                 + kurly.serviceType('LoadBalancer')
                 + kurly.serviceAnnotations({ 'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb' })).service;
    [svc.spec.type, svc.metadata.annotations],
    ['LoadBalancer', { 'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb' }]
  ),
  // The Service port is the contract with clients; the container port is not.
  service_port_is_separate_from_the_container_port: std.assertEqual(
    local a = kurly.http('web', 'img:1') + kurly.port(8080) + kurly.servicePort(443);
    [a.service.spec.ports[0].port, a.service.spec.ports[0].targetPort, a.deployment.spec.template.spec.containers[0].ports[0].containerPort],
    [443, 'http', 8080]
  ),
  // extraPort adds ports beside the primary http one: every declared port lands
  // on the container; only the exposed ones reach the Service, each targeting its
  // container port by name. servicePort defaults to the container port.
  extra_ports_reach_container_and_service: std.assertEqual(
    local a = kurly.http('mail', 'img:1')
              + kurly.port(8025)
              + kurly.extraPort('smtp', 1025)
              + kurly.extraPort('metrics', 9090, expose=false);
    [
      a.deployment.spec.template.spec.containers[0].ports,
      a.service.spec.ports,
    ],
    [
      [{ containerPort: 8025, name: 'http' }, { containerPort: 1025, name: 'smtp' }, { containerPort: 9090, name: 'metrics' }],
      [{ name: 'http', port: 80, targetPort: 'http' }, { name: 'smtp', port: 1025, targetPort: 'smtp' }],
    ]
  ),
  // A UDP extra port carries its protocol on both the container and the Service,
  // and a separate servicePort maps a client port to a different container port.
  extra_port_protocol_and_service_port: std.assertEqual(
    local a = kurly.http('dns', 'img:1')
              + kurly.extraPort('dns-udp', 53, servicePort=5353, protocol='UDP');
    [
      a.deployment.spec.template.spec.containers[0].ports[1],
      a.service.spec.ports[1],
    ],
    [
      { containerPort: 53, name: 'dns-udp', protocol: 'UDP' },
      { name: 'dns-udp', port: 5353, protocol: 'UDP', targetPort: 'dns-udp' },
    ]
  ),
  // Default unchanged: no type, no annotations, port 80.
  a_plain_service_is_unchanged: std.assertEqual(
    kurly.http('web', 'img:1').service.spec,
    { ports: [{ name: 'http', port: 80, targetPort: 'http' }], selector: { 'app.kubernetes.io/name': 'web' } }
  ),
  // Every Service a workload renders must agree on its families, including one a
  // workload writes for itself — a cluster that lacks the family rejects it, and
  // a Service left on the cluster default while its neighbours follow the
  // consumer is reachable over a family the rest of the workload does not speak.
  ip_families_reach_every_service: std.assertEqual(
    local items = kurly.list((import '../workloads/valkey/cache.libsonnet')()
                             + kurly.ipFamilies(['IPv6'], 'SingleStack')).items;
    [[s.metadata.name, s.spec.ipFamilies, s.spec.ipFamilyPolicy] for s in items if s.kind == 'Service'],
    [['valkey', ['IPv6'], 'SingleStack'], ['valkey-headless', ['IPv6'], 'SingleStack']]
  ),
  // Unset, kurly names none and the cluster's own default stands.
  ip_families_are_absent_by_default: std.assertEqual(
    std.objectHas(kurly.http('web', 'img:1').service.spec, 'ipFamilies'),
    false
  ),
  // supplementalGroups grants access to groups that already own shared storage;
  // it lands in the POD securityContext, alongside runAsNonRoot, not per-container.
  supplemental_groups_reach_pod_security: std.assertEqual(
    kurly.list(kurly.http('web', 'img:1') + kurly.supplementalGroups([2000, 3000]))
    .items[0].spec.template.spec.securityContext.supplementalGroups,
    [2000, 3000]
  ),
  // dns writes the three pod-level name-resolution fields and nothing when unset.
  dns_writes_pod_fields: std.assertEqual(
    local spec = kurly.list(kurly.http('web', 'img:1')
                            + kurly.dns(
                              policy='None',
                              config={ nameservers: ['10.0.0.10'], searches: ['corp.local'] },
                              hostAliases=[{ ip: '10.0.0.5', hostnames: ['db.internal'] }],
                            )).items[0].spec.template.spec;
    [spec.dnsPolicy, spec.dnsConfig.nameservers, spec.hostAliases[0].ip],
    ['None', ['10.0.0.10'], '10.0.0.5']
  ),
  dns_fields_absent_by_default: std.assertEqual(
    local spec = kurly.list(kurly.http('web', 'img:1')).items[0].spec.template.spec;
    [std.objectHas(spec, 'dnsPolicy'), std.objectHas(spec, 'dnsConfig'), std.objectHas(spec, 'hostAliases')],
    [false, false, false]
  ),
  // A workload named for its ENGINE leaks that engine into every consumer: a
  // client pointed at `valkey-headless` cannot be moved to dragonfly without
  // touching the client. Naming it for its ROLE is what makes the two
  // interchangeable — and it is also what lets a namespace hold two of them.
  valkey_cache_can_be_named_for_its_role: std.assertEqual(
    local items = kurly.list((import '../workloads/valkey/cache.libsonnet')(name='cache')).items;
    std.set([o.metadata.name for o in items]),
    ['cache', 'cache-headless']
  ),
  // The name reaches the plumbing too, not just the metadata: the init container
  // discovers peers through the headless Service BY NAME, so a half-renamed
  // workload looks right and never forms a replica set.
  a_renamed_cache_discovers_its_own_peers: std.assertEqual(
    local init = (import '../workloads/valkey/cache.libsonnet')(name='cache')
                 .deployment.spec.template.spec.initContainers[0];
    std.length(std.findSubstr('getent hosts cache-headless', init.command[2])) == 1,
    true
  ),
  // Two of the same workload in one namespace no longer collide.
  two_caches_coexist_in_one_namespace: std.assertEqual(
    local names(n) = [o.metadata.name for o in kurly.list((import '../workloads/valkey/cache.libsonnet')(name=n)).items];
    std.set(names('sessions') + names('fragments')),
    ['fragments', 'fragments-headless', 'sessions', 'sessions-headless']
  ),
  // An Ingress controller takes its per-route configuration from annotations and
  // nothing else, and the keys belong to whichever controller the cluster runs —
  // cert-manager, ingress-nginx, an AWS ALB. Without them the route renders and
  // the cluster does something other than what was asked.
  ingress_takes_annotations_and_tls: std.assertEqual(
    local ing = (kurly.http('web', 'img:1')
                 + kurly.expose.ingress('shop.example.com',
                                        ingressClass='nginx',
                                        annotations={ 'cert-manager.io/cluster-issuer': 'letsencrypt' },
                                        tls='shop-tls')).ingress;
    [ing.metadata.annotations, ing.spec.tls],
    [{ 'cert-manager.io/cluster-issuer': 'letsencrypt' }, [{ hosts: ['shop.example.com'], secretName: 'shop-tls' }]]
  ),
  // Naming no certificate leaves the route plain HTTP — a choice, not a default
  // worth hiding, and the same manifest as before.
  a_plain_ingress_is_unchanged: std.assertEqual(
    local spec = (kurly.http('web', 'img:1') + kurly.expose.ingress('shop.example.com')).ingress.spec;
    [std.objectHas(spec, 'tls'), std.length(spec.rules)],
    [false, 1]
  ),
  // A workload owning its listener and unable to terminate TLS cannot serve
  // HTTPS at all; the certificate is the cluster's to mint, so kurly only names it.
  own_gateway_terminates_tls_when_given_a_certificate: std.assertEqual(
    (kurly.http('web', 'img:1') + kurly.expose.ownGateway('shop.example.com', 'istio', tls='shop-tls'))
    .gateway.spec.listeners[0],
    {
      name: 'https',
      protocol: 'HTTPS',
      port: 443,
      hostname: 'shop.example.com',
      tls: { mode: 'Terminate', certificateRefs: [{ kind: 'Secret', name: 'shop-tls' }] },
      allowedRoutes: { namespaces: { from: 'Same' } },
    }
  ),
  own_listener_set_terminates_tls_when_given_a_certificate: std.assertEqual(
    (kurly.http('web', 'img:1') + kurly.expose.ownListenerSet('shop.example.com', 'shared', tls='shop-tls'))
    .listenerset.spec.listeners[0].protocol,
    'HTTPS'
  ),
  // guard sinks the given prefixes to a responder Service as a rule BEFORE the
  // catch-all; Gateway API's most-specific match makes the guarded prefix win.
  guard_prepends_a_sink_rule: std.assertEqual(
    (kurly.http('pad', 'img:1')
     + kurly.expose.listenerSet('pad.example.com', 'shared')
     + kurly.expose.guard(['/admin', '/stats'], 'not-found', serviceNamespace='shared-http-services'))
    .httproute.spec.rules,
    [
      {
        matches: [
          { path: { type: 'PathPrefix', value: '/admin' } },
          { path: { type: 'PathPrefix', value: '/stats' } },
        ],
        backendRefs: [{ name: 'not-found', namespace: 'shared-http-services', port: 5678 }],
      },
      {
        matches: [{ path: { type: 'PathPrefix', value: '/' } }],
        backendRefs: [{ name: 'pad', port: 80 }],
      },
    ]
  ),
  // Composed twice, guard adds one rule per call — different paths, different
  // responders. A same-namespace responder drops the namespace from the backendRef.
  guard_composes_more_than_once: std.assertEqual(
    std.length((kurly.http('pad', 'img:1')
                + kurly.expose.gateway('pad.example.com', 'shared')
                + kurly.expose.guard(['/admin'], 'forbidden')
                + kurly.expose.guard(['/metrics'], 'not-found')).httproute.spec.rules),
    3
  ),
  guard_same_namespace_omits_the_backend_namespace: std.assertEqual(
    (kurly.http('pad', 'img:1')
     + kurly.expose.gateway('pad.example.com', 'shared')
     + kurly.expose.guard(['/admin'], 'forbidden')).httproute.spec.rules[0].backendRefs[0],
    { name: 'forbidden', port: 5678 }
  ),
  // dns puts external-dns hints on the HTTPRoute's annotations; ttl stringifies
  // and a provider-specific passthrough merges in.
  dns_annotates_the_httproute: std.assertEqual(
    (kurly.http('web', 'img:1')
     + kurly.expose.gateway('web.example.com', 'shared')
     + kurly.expose.dns(target='ingress.example.net.', ttl=300, annotations={ 'external-dns.alpha.kubernetes.io/cloudflare-proxied': 'false' }))
    .httproute.metadata.annotations,
    {
      'external-dns.alpha.kubernetes.io/target': 'ingress.example.net.',
      'external-dns.alpha.kubernetes.io/ttl': '300',
      'external-dns.alpha.kubernetes.io/cloudflare-proxied': 'false',
    }
  ),
  // On an Ingress, the external-dns hints merge with the controller annotations.
  dns_merges_with_ingress_controller_annotations: std.assertEqual(
    (kurly.http('web', 'img:1')
     + kurly.expose.ingress('web.example.com', annotations={ 'nginx.ingress.kubernetes.io/x': 'y' })
     + kurly.expose.dns(hostname='alias.example.com'))
    .ingress.metadata.annotations,
    { 'nginx.ingress.kubernetes.io/x': 'y', 'external-dns.alpha.kubernetes.io/hostname': 'alias.example.com' }
  ),

  // probe attaches a Probe black-box-monitoring the given URL through a
  // blackbox-exporter, inheriting the workload's name and labels.
  probe_targets_the_url_through_blackbox: std.assertEqual(
    (kurly.http('web', 'img:1')
     + kurly.expose.gateway('web.example.com', 'shared')
     + kurly.expose.probe('web.example.com')).probe,
    {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'Probe',
      metadata: { name: 'web', labels: { 'app.kubernetes.io/managed-by': 'kurly', 'app.kubernetes.io/name': 'web' } },
      spec: {
        jobName: 'web',
        module: 'http_2xx',
        interval: '30s',
        prober: { url: 'blackbox-exporter:9115', path: '/probe' },
        targets: { staticConfig: { static: ['https://web.example.com'] } },
      },
    }
  ),

  // referenceGrant grants cross-namespace HTTPRoutes access to the workload's
  // Service, one `from` per namespace, the `to` fixed on the Service.
  reference_grant_lists_every_from_namespace: std.assertEqual(
    (kurly.http('not-found', 'img:1') + kurly.expose.referenceGrant(['team-a', 'team-b']))
    .referencegrant.spec,
    {
      from: [
        { group: 'gateway.networking.k8s.io', kind: 'HTTPRoute', namespace: 'team-a' },
        { group: 'gateway.networking.k8s.io', kind: 'HTTPRoute', namespace: 'team-b' },
      ],
      to: [{ group: '', kind: 'Service', name: 'not-found' }],
    }
  ),

  // The catch-all backendRef follows a servicePort override, so an exposure onto
  // a workload publishing a non-80 Service routes to the port that Service exposes.
  exposure_catch_all_follows_the_service_port: std.assertEqual(
    (kurly.http('api', 'img:1') + kurly.servicePort(8443) + kurly.expose.gateway('api.example.com', 'shared'))
    .httproute.spec.rules[0].backendRefs[0],
    { name: 'api', port: 8443 }
  ),

  // externalSecret authors an ESO ExternalSecret whose target Secret takes the
  // CR's own name, so it fills the exact name a workload parameter points at.
  // secretStoreRef and the data entries pass through verbatim.
  external_secret_targets_its_own_name: std.assertEqual(
    kurly.externalSecret('loki-storage', { name: 'vault', kind: 'ClusterSecretStore' }, [
      { secretKey: 'access_key_id', remoteRef: { key: 'loki/s3', property: 'access_key_id' } },
    ]),
    {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: { name: 'loki-storage', labels: { 'app.kubernetes.io/managed-by': 'kurly' } },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: { name: 'vault', kind: 'ClusterSecretStore' },
        target: { name: 'loki-storage' },
        data: [{ secretKey: 'access_key_id', remoteRef: { key: 'loki/s3', property: 'access_key_id' } }],
      },
    }
  ),
  external_secret_refresh_interval_is_overridable: std.assertEqual(
    kurly.externalSecret('s', { name: 'v' }, [], refreshInterval='15m').spec.refreshInterval,
    '15m'
  ),

  // certificate authors a cert-manager Certificate whose secretName defaults to
  // its own name, so a workload's tls parameter pointed at that name lines up.
  certificate_defaults_secret_name_to_its_own: std.assertEqual(
    kurly.certificate('storefront-tls', ['storefront.example.com'], 'letsencrypt-prod'),
    {
      apiVersion: 'cert-manager.io/v1',
      kind: 'Certificate',
      metadata: { name: 'storefront-tls', labels: { 'app.kubernetes.io/managed-by': 'kurly' } },
      spec: {
        secretName: 'storefront-tls',
        issuerRef: { name: 'letsencrypt-prod', kind: 'ClusterIssuer', group: 'cert-manager.io' },
        dnsNames: ['storefront.example.com'],
      },
    }
  ),
  // A namespaced Issuer and the optional lifetime knobs flow through; unset
  // duration/renewBefore are pruned rather than rendered null.
  certificate_takes_issuer_kind_and_lifetime: std.assertEqual(
    kurly.certificate('c', ['a.example.com'], 'ca', secretName='c-tls', issuerKind='Issuer', duration='2160h', renewBefore='360h').spec,
    {
      secretName: 'c-tls',
      issuerRef: { name: 'ca', kind: 'Issuer', group: 'cert-manager.io' },
      dnsNames: ['a.example.com'],
      duration: '2160h',
      renewBefore: '360h',
    }
  ),

  // A dedicated Gateway provisions a real load balancer, configured through
  // annotations whose keys belong to the implementation.
  own_gateway_takes_annotations: std.assertEqual(
    (kurly.http('web', 'img:1') + kurly.expose.ownGateway('shop.example.com',
                                                          'istio',
                                                          annotations={ 'networking.gke.io/x': 'y' }))
    .gateway.metadata.annotations,
    { 'networking.gke.io/x': 'y' }
  ),
}
