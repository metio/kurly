// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Metamorphic tests: pin the BLAST RADIUS of each feature — composing it changes
// exactly what it should and nothing else. Each field asserts the delta between
// a base workload and the base plus one feature.
local kurly = import '../main.libsonnet';

local base = kurly.http('m', 'ghcr.io/example/m:1.0.0');
local basePod = base.deployment.spec.template.spec;
local mainContainer(app) = app.deployment.spec.template.spec.containers[0];

{
  // scratch adds exactly one volume (and the base had none).
  scratch_adds_one_volume: std.assertEqual(
    [
      std.objectHas(basePod, 'volumes'),
      std.length((base + kurly.scratch('/tmp')).deployment.spec.template.spec.volumes),
    ],
    [false, 1]
  ),
  // security.privileged strips every container security field — no securityContext
  // at all on the container.
  privileged_removes_container_security: std.assertEqual(
    std.objectHas(mainContainer(base + kurly.security.privileged), 'securityContext'),
    false
  ),
  // replicas(n) changes the replica count and nothing else in the Deployment.
  replicas_changes_only_count: std.assertEqual(
    (base + kurly.replicas(7)).deployment,
    base.deployment { spec+: { replicas: 7 } }
  ),
  // nodeSelector adds only the nodeSelector to the pod spec.
  node_selector_adds_only_itself: std.assertEqual(
    (base + kurly.nodeSelector({ role: 'edge' })).deployment.spec.template.spec,
    basePod { nodeSelector: { role: 'edge' } }
  ),
  // env is additive: two env features accumulate, neither clobbers the other.
  env_accumulates: std.assertEqual(
    std.length((base + kurly.env({ A: '1' }) + kurly.env({ B: '2' })).deployment.spec.template.spec.containers[0].env),
    2
  ),
  // writableRootFilesystem flips exactly one knob: the container's
  // readOnlyRootFilesystem field disappears, the rest of the posture stays.
  writable_root_flips_one_knob: std.assertEqual(
    [
      std.objectHas(mainContainer(base).securityContext, 'readOnlyRootFilesystem'),
      std.objectHas(mainContainer(base + kurly.writableRootFilesystem()).securityContext, 'readOnlyRootFilesystem'),
      mainContainer(base + kurly.writableRootFilesystem()).securityContext.allowPrivilegeEscalation,
    ],
    [true, false, false]
  ),
}
