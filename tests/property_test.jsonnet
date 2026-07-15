// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Property and parameterized tests: rather than one example per function (that is
// what the coverage battery does), these exercise each input-taking function
// across MULTIPLE inputs — every branch of the ones with logic, and a range of
// values for the ones that must round-trip a property. Every field is a
// std.assertEqual, checked like the rest of the suite.
local kurly = import '../main.libsonnet';

local httpBase = kurly.http('p', 'ghcr.io/example/p:1.0.0');
local podOf(app) = app.deployment.spec.template.spec;
local containerOf(app) = podOf(app).containers[0];
// Does every entry of `sub` appear, with the same value, in `whole`?
local subsetOf(sub, whole) = std.all([std.objectHas(whole, k) && whole[k] == sub[k] for k in std.objectFields(sub)]);

{
  // --- parameterized: every branch of the functions with logic ---------------

  // resourcePreset renders the documented memory request for every named size.
  resource_preset_sizes: std.assertEqual(
    [
      containerOf(httpBase + kurly.resourcePreset(p)).resources.requests.memory
      for p in ['nano', 'micro', 'small', 'medium', 'large']
    ],
    ['64Mi', '128Mi', '256Mi', '512Mi', '1Gi']
  ),
  // …and each keeps the documented shape: memory limit == request, no CPU limit.
  resource_preset_shape: std.assertEqual(
    std.all([
      local r = containerOf(httpBase + kurly.resourcePreset(p)).resources;
      r.limits.memory == r.requests.memory && !std.objectHas(r.limits, 'cpu')
      for p in ['nano', 'micro', 'small', 'medium', 'large']
    ]),
    true
  ),
  // hpa builds the right metric set for cpu-only, memory-only, and both.
  hpa_metric_branches: std.assertEqual(
    [
      [m.resource.name for m in (httpBase + kurly.hpa(1, 5, targetCPU=80)).hpa.spec.metrics],
      [m.resource.name for m in (httpBase + kurly.hpa(1, 5, targetMemory=70)).hpa.spec.metrics],
      [m.resource.name for m in (httpBase + kurly.hpa(1, 5, targetCPU=80, targetMemory=70)).hpa.spec.metrics],
    ],
    [['cpu'], ['memory'], ['cpu', 'memory']]
  ),
  // pdb keeps whichever bound is set and only that one.
  pdb_branches: std.assertEqual(
    [
      std.objectHas((httpBase + kurly.pdb(minAvailable=2)).pdb.spec, 'minAvailable'),
      std.objectHas((httpBase + kurly.pdb(minAvailable=2)).pdb.spec, 'maxUnavailable'),
      std.objectHas((httpBase + kurly.pdb(maxUnavailable=1)).pdb.spec, 'maxUnavailable'),
      std.objectHas((httpBase + kurly.pdb(maxUnavailable=1)).pdb.spec, 'minAvailable'),
    ],
    [true, false, true, false]
  ),
  // store is a shared PVC on a Deployment kind but a per-pod volumeClaimTemplate
  // on a StatefulSet — the same feature, kind-appropriate.
  store_kind_branches: std.assertEqual(
    local stateful = kurly.stateful('s', 'ghcr.io/example/s:1.0.0') + kurly.store('/d', '1Gi');
    [
      (httpBase + kurly.store('/d', '1Gi')).storeClaim.kind,
      stateful.storeClaim,
      std.length(stateful.statefulset.spec.volumeClaimTemplates),
    ],
    ['PersistentVolumeClaim', null, 1]
  ),
  // each security profile sets its documented posture.
  security_profile_branches: std.assertEqual(
    [
      containerOf(httpBase + kurly.security.restricted).securityContext.readOnlyRootFilesystem,
      containerOf(httpBase + kurly.security.baseline).securityContext.readOnlyRootFilesystem,
      std.objectHas(containerOf(httpBase + kurly.security.privileged), 'securityContext'),
    ],
    [true, true, false]
  ),

  // --- property: a value must round-trip, for a range of inputs --------------

  // For ANY replica count, the Deployment echoes it exactly.
  replicas_roundtrip: std.assertEqual(
    std.all([(httpBase + kurly.replicas(n)).deployment.spec.replicas == n for n in std.range(1, 12)]),
    true
  ),
  // For ANY run-as uid, container runAsUser and pod fsGroup reflect it.
  runas_roundtrip: std.assertEqual(
    std.all([
      local a = httpBase + kurly.runAs(uid);
      containerOf(a).securityContext.runAsUser == uid && podOf(a).securityContext.fsGroup == uid
      for uid in [1, 100, 1000, 12345, 65534]
    ]),
    true
  ),
  // For ANY podLabels map, its entries reach the pod template and NONE reach the
  // immutable selector.
  pod_labels_property: std.assertEqual(
    std.all([
      local a = httpBase + kurly.podLabels(m);
      subsetOf(m, a.deployment.spec.template.metadata.labels)
      && std.all([!std.objectHas(a.deployment.spec.selector.matchLabels, k) for k in std.objectFields(m)])
      for m in [{ a: '1' }, { tier: 'db', zone: 'a' }, { 'app.example/role': 'primary' }]
    ]),
    true
  ),
  // For ANY env map, every key becomes a container EnvVar with the same value.
  env_property: std.assertEqual(
    std.all([
      local vars = containerOf(httpBase + kurly.env(m)).env;
      local byName = { [v.name]: v.value for v in vars };
      std.length(vars) == std.length(std.objectFields(m)) && std.all([byName[k] == m[k] for k in std.objectFields(m)])
      for m in [{ A: '1' }, { A: '1', B: '2' }, { LOG: 'debug', PORT: '8080', X: 'y' }]
    ]),
    true
  ),
  // For ANY resources(requests, limits), the container echoes them exactly.
  resources_roundtrip: std.assertEqual(
    std.all([
      local a = httpBase + kurly.resources(requests=r.req, limits=r.lim);
      containerOf(a).resources.requests == r.req && containerOf(a).resources.limits == r.lim
      for r in [
        { req: { cpu: '100m', memory: '128Mi' }, lim: { memory: '256Mi' } },
        { req: { cpu: '1', memory: '1Gi' }, lim: { cpu: '2', memory: '2Gi' } },
      ]
    ]),
    true
  ),
  // Pass-through scheduling features round-trip their value into the pod spec
  // unchanged, for several distinct inputs.
  node_selector_roundtrip: std.assertEqual(
    std.all([
      podOf(httpBase + kurly.nodeSelector(m)).nodeSelector == m
      for m in [{ a: '1' }, { disktype: 'ssd', zone: 'eu' }]
    ]),
    true
  ),
  tolerations_roundtrip: std.assertEqual(
    std.all([
      podOf(httpBase + kurly.tolerations(t)).tolerations == t
      for t in [
        [{ key: 'a', operator: 'Exists' }],
        [{ key: 'gpu', operator: 'Equal', value: 'yes', effect: 'NoSchedule' }],
      ]
    ]),
    true
  ),
  // For ANY replica count on a StatefulSet, it echoes too (the new kind shares
  // the property).
  stateful_replicas_roundtrip: std.assertEqual(
    std.all([
      (kurly.stateful('s', 'ghcr.io/example/s:1.0.0') + kurly.replicas(n)).statefulset.spec.replicas == n
      for n in std.range(1, 8)
    ]),
    true
  ),
}
