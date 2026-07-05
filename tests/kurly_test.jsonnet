// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Assertion suite: every field evaluates to true (std.assertEqual raises on
// mismatch), so `jsonnet -J vendor tests/kurly_test.jsonnet` is the test run.
local kurly = import '../main.libsonnet';

local shop = kurly.http.new('shop', 'ghcr.io/example/shop:1.2.3')
             .withReplicas(3)
             .withLabels({ team: 'storefront' })
             .withEnv({ ZED: 'last' })
             .withEnv({ ALPHA: 'first' })
             .withHttpProbes('/health');

local ingressed = shop + kurly.expose.ingress('shop.example.com', ingressClass='nginx');

local routed = shop + kurly.expose.gateway('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure', sectionName='https');

local api = kurly.http.new('users', 'ghcr.io/example/users:2.0.0')
            .withPort(3000)
            .withResources(limits={ memory: '256Mi' })
            .withAnnotations({ 'example.com/scrape': 'true' });

local worker = kurly.worker.new('mailer', 'ghcr.io/example/mailer:1.0.0')
               .withReplicas(4)
               .withServiceAccount('mailer');

local cron = kurly.cron.new('backup', 'ghcr.io/example/backup:1.0.0', '13 3 * * *')
             .withServiceAccount('backup');

local daemon = kurly.daemon.new('node-agent', 'ghcr.io/example/agent:1.0.0');

{
  // --- http ------------------------------------------------------------------
  http_replicas: std.assertEqual(shop.deployment.spec.replicas, 3),
  http_image: std.assertEqual(shop.deployment.spec.template.spec.containers[0].image, 'ghcr.io/example/shop:1.2.3'),

  // User labels land on metadata and the pod template, but never in the
  // immutable selector.
  http_selector_is_stable: std.assertEqual(
    shop.deployment.spec.selector.matchLabels,
    { name: 'shop', 'app.kubernetes.io/name': 'shop' }
  ),
  http_user_labels_on_metadata: std.assertEqual(shop.deployment.metadata.labels.team, 'storefront'),
  http_user_labels_on_pods: std.assertEqual(shop.deployment.spec.template.metadata.labels.team, 'storefront'),

  // The env map renders as a sorted array, so rendered output is deterministic
  // regardless of the order withEnv calls added the variables.
  http_env_sorted: std.assertEqual(
    shop.deployment.spec.template.spec.containers[0].env,
    [{ name: 'ALPHA', value: 'first' }, { name: 'ZED', value: 'last' }]
  ),

  http_probes: std.assertEqual(
    shop.deployment.spec.template.spec.containers[0].readinessProbe.httpGet,
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
    api.deployment.spec.template.spec.containers[0].ports,
    [{ containerPort: 3000, name: 'http' }]
  ),

  // withResources merges: adding limits keeps the default requests.
  http_limits_added: std.assertEqual(
    api.deployment.spec.template.spec.containers[0].resources,
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

  // Exposures compose: running Ingress and Gateway API side by side (e.g.
  // during a migration) renders both, each with its own host.
  dual_exposure: std.assertEqual(
    local both = shop
                 + kurly.expose.ingress('old.example.com')
                 + kurly.expose.gateway('new.example.com', 'shared');
    [std.length(kurly.list(both).items), both.ingress.spec.rules[0].host, both.httproute.spec.hostnames],
    [4, 'old.example.com', ['new.example.com']]
  ),

  // --- worker ----------------------------------------------------------------
  worker_replicas: std.assertEqual(worker.deployment.spec.replicas, 4),
  worker_no_service: std.assertEqual(std.objectHas(worker, 'service'), false),
  worker_no_ports: std.assertEqual(
    std.objectHas(worker.deployment.spec.template.spec.containers[0], 'ports'),
    false
  ),
  worker_service_account: std.assertEqual(
    worker.deployment.spec.template.spec.serviceAccountName,
    'mailer'
  ),

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
  cron_reschedule: std.assertEqual(cron.withSchedule('0 4 * * *').cronjob.spec.schedule, '0 4 * * *'),

  // --- daemon ----------------------------------------------------------------
  daemon_kind: std.assertEqual(daemon.daemonset.kind, 'DaemonSet'),
  daemon_selector: std.assertEqual(
    daemon.daemonset.spec.selector.matchLabels,
    { name: 'node-agent', 'app.kubernetes.io/name': 'node-agent' }
  ),

  // --- list ------------------------------------------------------------------
  list_kind: std.assertEqual(kurly.list(ingressed).kind, 'List'),
  list_renders_all_manifests: std.assertEqual(std.length(kurly.list(ingressed).items), 3),
  list_gateway_mode: std.assertEqual(std.length(kurly.list(routed).items), 3),
  list_worker_has_only_deployment: std.assertEqual(std.length(kurly.list(worker).items), 1),

  // Modifiers late-bind: an image swap after exposure still lands in the
  // rendered container.
  late_binding: std.assertEqual(
    routed.withImage('ghcr.io/example/shop:2.0.0').deployment.spec.template.spec.containers[0].image,
    'ghcr.io/example/shop:2.0.0'
  ),

  // --- Pod Security Standards (restricted) ------------------------------------
  // Every kind ships the full restricted profile by default.
  pss_pod_security_context: std.assertEqual(
    shop.deployment.spec.template.spec.securityContext,
    { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } }
  ),
  pss_user_namespace: std.assertEqual(shop.deployment.spec.template.spec.hostUsers, false),
  pss_container_hardening: std.assertEqual(
    shop.deployment.spec.template.spec.containers[0].securityContext,
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
  pss_no_token_by_default: std.assertEqual(
    shop.deployment.spec.template.spec.automountServiceAccountToken,
    false
  ),
  pss_token_with_service_account: std.assertEqual(
    worker.deployment.spec.template.spec.automountServiceAccountToken,
    true
  ),

  // Escape hatches downgrade exactly one default and leave the rest intact.
  // A relaxed knob omits its field rather than writing the Kubernetes default.
  hatch_root_user: std.assertEqual(
    shop.withRootUser().deployment.spec.template.spec.securityContext,
    { seccompProfile: { type: 'RuntimeDefault' } }
  ),
  hatch_writable_root_filesystem: std.assertEqual(
    std.objectHas(
      shop.withWritableRootFilesystem().deployment.spec.template.spec.containers[0].securityContext,
      'readOnlyRootFilesystem'
    ),
    false
  ),
  hatch_host_users: std.assertEqual(
    std.objectHas(shop.withHostUsers().deployment.spec.template.spec, 'hostUsers'),
    false
  ),
  hatch_host_users_keeps_profile: std.assertEqual(
    shop.withHostUsers().deployment.spec.template.spec.securityContext.runAsNonRoot,
    true
  ),

  // --- security profiles -------------------------------------------------------
  // Profiles compose with `+` like exposures; each sets every security knob,
  // so the last profile wins and hatches still fine-tune afterwards.

  // Explicitly composing the default is a no-op.
  security_restricted_is_default: std.assertEqual(
    (shop + kurly.security.restricted).deployment.spec.template.spec,
    shop.deployment.spec.template.spec
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

  // Hatches fine-tune after a profile: baseline plus host user namespaces.
  security_profile_then_hatch: std.assertEqual(
    local spec = (shop + kurly.security.baseline).withHostUsers().deployment.spec.template.spec;
    [std.objectHas(spec, 'hostUsers'), spec.containers[0].securityContext.readOnlyRootFilesystem],
    [false, true]
  ),

  // Profiles work on every kind, not just Deployments.
  security_baseline_on_cron: std.assertEqual(
    std.objectHas((cron + kurly.security.baseline).cronjob.spec.jobTemplate.spec.template.spec, 'securityContext'),
    false
  ),
}
