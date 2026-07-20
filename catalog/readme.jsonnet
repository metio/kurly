// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Generates the maturity badge and the JaaS/stageset deploy walkthrough that
// every workload README carries, from the machine-readable catalog. gen-readme.sh
// splices each workload's section into its README between the generated markers,
// and check-readme.sh fails if a committed README has drifted — so the deploy
// instructions can never fall out of step with a workload's stages or kind.
//
// The output is an object keyed by workload id whose values are the markdown
// sections (without the surrounding markers, which the splicer adds).
local catalog = import './catalog.json';

// A jsonnet identifier for a stage's import alias (dashes are illegal there).
local alias(name) = std.strReplace(name, '-', '_');

// The ready-check GVK for a stage's kind. Deployment-shaped kinds converge to a
// ready state worth gating on; a CronJob or Job does not (it runs to completion),
// so those stages carry no ready check.
local readyGvk = {
  http: { apiVersion: 'apps/v1', kind: 'Deployment' },
  worker: { apiVersion: 'apps/v1', kind: 'Deployment' },
  stateful: { apiVersion: 'apps/v1', kind: 'StatefulSet' },
  daemon: { apiVersion: 'apps/v1', kind: 'DaemonSet' },
};

local tierBlurb = {
  rendered: 'renders and validates against the Kubernetes schemas with its defaults.',
  tested: 'has workload-specific assertions in the test suite, on top of rendering cleanly.',
  e2e: 'is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.',
};

// The maturity section: the derived tier, plus the operator-attested production
// record when there is one.
local maturitySection(w) =
  local m = w.maturity;
  local prod =
    if std.objectHas(m, 'production')
    then ' In production since %s on the %s cluster.' % [m.production.since, m.production.cluster]
    else '';
  std.join('\n', [
    '## Maturity',
    '',
    '**%s** — this workload %s%s' % [m.tier, tierBlurb[m.tier], prod],
  ]);

// For a workload with one stage the resources take the workload's own name; with
// several they are conventionally prefixed per stage (e.g. mailu-front). The
// snippet that renders a stage is named to match.
local single(w) = std.length(w.stages) == 1;
local resourceName(w, stage) = if single(w) then w.id else '%s-%s' % [w.id, stage.id];
local snippetName(w, stage) = resourceName(w, stage);

// One JsonnetSnippet per stage: it imports the stage by its canonical path and
// renders it with kurly.list, importing both the recipes and this workload's
// source as libraries.
local snippetYaml(w, stage) = std.join('\n', [
  'apiVersion: jaas.metio.wtf/v1',
  'kind: JsonnetSnippet',
  'metadata: { name: %s, namespace: %s }' % [snippetName(w, stage), w.id],
  'spec:',
  '  serviceAccountName: %s-renderer' % w.id,
  '  files:',
  '    main.jsonnet: |',
  "      local kurly = import 'github.com/metio/kurly/main.libsonnet';",
  "      local %s = import '%s';" % [alias(stage.id), stage.importPath],
  '      // Compose your exposure and any + features here, then render.',
  '      kurly.list(%s())' % alias(stage.id),
  '  libraries:',
  '    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }',
  '    - { kind: JsonnetLibrary, name: kurly-%s, importPath: github.com/metio/kurly/workloads/%s }' % [w.id, w.id],
]);

// The Flux/JaaS sources shared by every stage, then a snippet per stage.
local sourcesYaml(w) = std.join('\n---\n', [
  std.join('\n', [
    '# The kurly library (recipes) and this workload (source), both single-layer',
    '# images from their release pipelines, pulled by plain OCIRepositories.',
    'apiVersion: source.toolkit.fluxcd.io/v1',
    'kind: OCIRepository',
    'metadata: { name: kurly, namespace: %s }' % w.id,
    'spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }',
  ]),
  std.join('\n', [
    'apiVersion: source.toolkit.fluxcd.io/v1',
    'kind: OCIRepository',
    'metadata: { name: kurly-%s, namespace: %s }' % [w.id, w.id],
    'spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/%s, ref: { tag: latest } }' % w.id,
  ]),
  std.join('\n', [
    'apiVersion: jaas.metio.wtf/v1',
    'kind: JsonnetLibrary',
    'metadata: { name: kurly, namespace: %s }' % w.id,
    'spec: { sourceRef: { kind: OCIRepository, name: kurly } }',
  ]),
  std.join('\n', [
    'apiVersion: jaas.metio.wtf/v1',
    'kind: JsonnetLibrary',
    'metadata: { name: kurly-%s, namespace: %s }' % [w.id, w.id],
    'spec: { sourceRef: { kind: OCIRepository, name: kurly-%s } }' % w.id,
  ]),
] + [snippetYaml(w, stage) for stage in w.stages]);

// A single stage entry in the StageSet: it names the snippet that produced its
// artifact, and gates on the workload object becoming ready where that is meaningful.
local stageEntry(w, stage) =
  local head = [
    '    - name: %s' % stage.id,
    '      sourceRef:',
    '        apiVersion: jaas.metio.wtf/v1',
    '        kind: JsonnetSnippet',
    '        name: %s' % snippetName(w, stage),
  ];
  local ready =
    if std.objectHas(readyGvk, stage.kind)
    then [
      '      readyChecks:',
      '        checks:',
      '          - { apiVersion: %s, kind: %s, name: %s }' % [
        readyGvk[stage.kind].apiVersion,
        readyGvk[stage.kind].kind,
        resourceName(w, stage),
      ],
    ]
    else [];
  std.join('\n', head + ready);

local stageSetYaml(w) = std.join('\n', [
  'apiVersion: stages.metio.wtf/v1',
  'kind: StageSet',
  'metadata: { name: %s, namespace: %s }' % [w.id, w.id],
  'spec:',
  '  serviceAccountName: %s-deployer' % w.id,
  '  rollbackOnFailure: true',
  '  stages:',
] + [stageEntry(w, stage) for stage in w.stages]);

local stageWord(w) = if single(w) then 'stage' else 'stages';

local deploySection(w) = std.join('\n', [
  '## Deploy with JaaS',
  '',
  'Make the kurly library and this workload importable as `JsonnetLibrary`s, render',
  'each %s with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images' % stageWord(w),
  'are single-layer, so a plain Flux `OCIRepository` pulls each one directly.',
  '',
  '```yaml',
  sourcesYaml(w),
  '```',
  '',
  'A `StageSet` deploys the %s in order, pinning artifact revisions at the start of' % stageWord(w),
  'the run and gating each stage before the next.',
  '',
  '```yaml',
  stageSetYaml(w),
  '```',
]);

local section(w) = std.join('\n\n', [
  maturitySection(w),
  deploySection(w),
]);

{
  [w.id]: section(w)
  for w in catalog.workloads
}
