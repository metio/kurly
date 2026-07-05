// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Assertion suite: every field evaluates to true (std.assertEqual raises on
// mismatch), so `jsonnet -J vendor tests/kurly_test.jsonnet` is the test run.
local kurly = import '../main.libsonnet';

local web = kurly.web.new('shop', 'ghcr.io/example/shop:1.2.3')
            .withReplicas(3)
            .withLabels({ team: 'storefront' })
            .withEnv({ ZED: 'last' })
            .withEnv({ ALPHA: 'first' })
            .withHttpProbes('/health')
            .withIngressClass('nginx')
            .withHost('shop.example.com');

local api = kurly.api.new('users', 'ghcr.io/example/users:2.0.0')
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
  // --- web -----------------------------------------------------------------
  web_replicas: std.assertEqual(web.deployment.spec.replicas, 3),
  web_image: std.assertEqual(web.deployment.spec.template.spec.containers[0].image, 'ghcr.io/example/shop:1.2.3'),

  // User labels land on metadata and the pod template, but never in the
  // immutable selector.
  web_selector_is_stable: std.assertEqual(
    web.deployment.spec.selector.matchLabels,
    { name: 'shop', 'app.kubernetes.io/name': 'shop' }
  ),
  web_user_labels_on_metadata: std.assertEqual(web.deployment.metadata.labels.team, 'storefront'),
  web_user_labels_on_pods: std.assertEqual(web.deployment.spec.template.metadata.labels.team, 'storefront'),

  // The env map renders as a sorted array, so rendered output is deterministic
  // regardless of the order withEnv calls added the variables.
  web_env_sorted: std.assertEqual(
    web.deployment.spec.template.spec.containers[0].env,
    [{ name: 'ALPHA', value: 'first' }, { name: 'ZED', value: 'last' }]
  ),

  web_probes: std.assertEqual(
    web.deployment.spec.template.spec.containers[0].readinessProbe.httpGet,
    { path: '/health', port: 'http' }
  ),

  web_service_targets_named_port: std.assertEqual(
    web.service.spec.ports,
    [{ name: 'http', port: 80, targetPort: 'http' }]
  ),
  web_service_selector_matches_pods: std.assertEqual(
    web.service.spec.selector,
    { 'app.kubernetes.io/name': 'shop' }
  ),

  web_ingress_host: std.assertEqual(web.ingress.spec.rules[0].host, 'shop.example.com'),
  web_ingress_class: std.assertEqual(web.ingress.spec.ingressClassName, 'nginx'),
  web_ingress_backend: std.assertEqual(
    web.ingress.spec.rules[0].http.paths[0].backend.service,
    { name: 'shop', port: { name: 'http' } }
  ),

  // Without withHost there is no Ingress to render.
  web_no_ingress_by_default: std.assertEqual(
    std.objectHas(kurly.web.new('plain', 'img:1'), 'ingress'),
    false
  ),

  // --- api -----------------------------------------------------------------
  api_port_override: std.assertEqual(
    api.deployment.spec.template.spec.containers[0].ports,
    [{ containerPort: 3000, name: 'http' }]
  ),

  // withResources merges: adding limits keeps the default requests.
  api_limits_added: std.assertEqual(
    api.deployment.spec.template.spec.containers[0].resources,
    { requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } }
  ),

  api_annotations_on_metadata: std.assertEqual(api.deployment.metadata.annotations, { 'example.com/scrape': 'true' }),
  api_annotations_on_pods: std.assertEqual(
    api.deployment.spec.template.metadata.annotations,
    { 'example.com/scrape': 'true' }
  ),

  api_has_service: std.assertEqual(std.objectHas(api, 'service'), true),

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
  list_kind: std.assertEqual(kurly.list(web).kind, 'List'),
  list_renders_all_manifests: std.assertEqual(std.length(kurly.list(web).items), 3),
  list_worker_has_only_deployment: std.assertEqual(std.length(kurly.list(worker).items), 1),

  // Modifiers late-bind: an image swap after other modifiers still lands in
  // the rendered container.
  late_binding: std.assertEqual(
    web.withImage('ghcr.io/example/shop:2.0.0').deployment.spec.template.spec.containers[0].image,
    'ghcr.io/example/shop:2.0.0'
  ),

  // --- Pod Security Standards (restricted) ------------------------------------
  // Every kind ships the full restricted profile by default.
  pss_pod_security_context: std.assertEqual(
    web.deployment.spec.template.spec.securityContext,
    { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } }
  ),
  pss_user_namespace: std.assertEqual(web.deployment.spec.template.spec.hostUsers, false),
  pss_container_hardening: std.assertEqual(
    web.deployment.spec.template.spec.containers[0].securityContext,
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
    web.deployment.spec.template.spec.automountServiceAccountToken,
    false
  ),
  pss_token_with_service_account: std.assertEqual(
    worker.deployment.spec.template.spec.automountServiceAccountToken,
    true
  ),

  // Escape hatches downgrade exactly one default and leave the rest intact.
  hatch_root_user: std.assertEqual(
    web.withRootUser().deployment.spec.template.spec.securityContext,
    { runAsNonRoot: false, seccompProfile: { type: 'RuntimeDefault' } }
  ),
  hatch_writable_root_filesystem: std.assertEqual(
    web.withWritableRootFilesystem().deployment.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem,
    false
  ),
  hatch_host_users: std.assertEqual(
    std.objectHas(web.withHostUsers().deployment.spec.template.spec, 'hostUsers'),
    false
  ),
  hatch_host_users_keeps_profile: std.assertEqual(
    web.withHostUsers().deployment.spec.template.spec.securityContext.runAsNonRoot,
    true
  ),
}
