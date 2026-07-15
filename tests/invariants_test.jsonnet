// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Invariants: properties that must hold for EVERY workload kurly renders,
// asserted over a diverse set of compositions rather than one example. If a
// change ever breaks one of these for any kind or feature mix, a field here
// flips to false.
local kurly = import '../main.libsonnet';

// A spread of compositions across all kinds and the main feature axes.
local apps = [
  kurly.http('web', 'ghcr.io/example/web:1.2.3'),
  kurly.http('web2', 'ghcr.io/example/web:1.2.3') + kurly.expose.ingress('web.example.com') + kurly.labels({ team: 'edge' }),
  kurly.http('web3', 'ghcr.io/example/web:1.2.3') + kurly.expose.gateway('web.example.com', 'shared'),
  kurly.worker('queue', 'ghcr.io/example/queue:1.0.0') + kurly.replicas(2) + kurly.resourcePreset('small'),
  kurly.cron('nightly', 'ghcr.io/example/nightly:1.0.0', '0 2 * * *'),
  kurly.daemon('agent', 'ghcr.io/example/agent:1.0.0') + kurly.nodeSelector({ role: 'edge' }),
  kurly.http('stateful', 'ghcr.io/example/stateful:1.0.0') + kurly.store('/data', '1Gi') + kurly.recreate() + kurly.config({ 'a.conf': 'x' }),
];

local allManifests = std.flattenArrays([kurly.list(a).items for a in apps]);

// The one pod-bearing manifest of an app (Deployment/CronJob/DaemonSet).
local podSpecOf(app) =
  if std.objectHas(app, 'deployment') then app.deployment.spec.template.spec
  else if std.objectHas(app, 'cronjob') then app.cronjob.spec.jobTemplate.spec.template.spec
  else app.daemonset.spec.template.spec;
local mainContainerOf(app) = podSpecOf(app).containers[0];

// An app that carries a user label, to prove it never reaches the selector.
local labelled = kurly.http('labelled', 'ghcr.io/example/labelled:1.0.0') + kurly.labels({ team: 'payments' });

{
  // Every rendered manifest carries the managed-by label — the ownership marker
  // policy and tooling key on.
  managed_by_everywhere: std.assertEqual(
    std.all([
      std.objectHas(m.metadata, 'labels') && std.get(m.metadata.labels, 'app.kubernetes.io/managed-by', '') == 'kurly'
      for m in allManifests
    ]),
    true
  ),
  // Every container image is tag-pinned and never `:latest`.
  images_tag_pinned: std.assertEqual(
    std.all([
      local img = mainContainerOf(a).image;
      std.length(std.findSubstr(':', img)) > 0 && !std.endsWith(img, ':latest')
      for a in apps
    ]),
    true
  ),
  // Every workload sets resource requests (no unbounded pods).
  requests_always_set: std.assertEqual(
    std.all([std.objectHas(mainContainerOf(a).resources, 'requests') for a in apps]),
    true
  ),
  // The default posture is restricted: read-only root fs, non-root, no privilege
  // escalation, all capabilities dropped — on a workload that relaxes nothing.
  restricted_by_default: std.assertEqual(
    local sc = mainContainerOf(apps[0]).securityContext;
    [sc.readOnlyRootFilesystem, sc.allowPrivilegeEscalation, sc.capabilities.drop],
    [true, false, ['ALL']]
  ),
  // User labels reach metadata and the pod template, but NEVER the immutable
  // selector — a leak there would break a `helm upgrade`-style in-place update.
  user_label_not_in_selector: std.assertEqual(
    [
      std.objectHas(labelled.deployment.spec.selector.matchLabels, 'team'),
      std.get(labelled.deployment.spec.template.metadata.labels, 'team', null),
    ],
    [false, 'payments']
  ),
  // A workload's selector is exactly its stable labels (kurly's own name label
  // plus the `name` label k8s-libsonnet's constructor forces) — nothing volatile
  // (version, managed-by, user labels) leaks into the immutable field.
  selector_is_stable: std.assertEqual(
    kurly.http('sel', 'ghcr.io/example/sel:1.0.0').deployment.spec.selector.matchLabels,
    { 'app.kubernetes.io/name': 'sel', name: 'sel' }
  ),
}
