// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Generates catalog.json: the machine-readable model of kurly's public API the
// assembler UI (and any docs renderer) reads. The annotations carry the prose,
// parameter types, and composition facets; this file cross-checks them against
// the REAL exported fields of each library module and fails to render if the two
// diverge — so a feature added without an annotation, or an annotation left
// behind after a feature is removed, breaks the build rather than shipping a
// catalog that lies. Render from the repo root:
//
//   jsonnet -J vendor catalog/catalog.jsonnet > catalog/catalog.json
local expose = import '../lib/expose.libsonnet';
local features = import '../lib/features.libsonnet';
local migrations = import '../lib/migrations.libsonnet';
local security = import '../lib/security.libsonnet';
local main = import '../main.libsonnet';
local ann = import './annotations.libsonnet';

// Each workload stage, imported by the canonical path a consumer's snippet uses
// (resolved via the vendor/github.com/metio/kurly symlink check-catalog creates).
// A stage that is renamed or removed fails the import here; the reconcile below
// fails if this map and the annotations fall out of step.
local stageImports = {
  'tik/backend': import 'github.com/metio/kurly/workloads/tik/backend.libsonnet',
  'forgejo/server': import 'github.com/metio/kurly/workloads/forgejo/server.libsonnet',
  'vaultwarden/server': import 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet',
  'netbox/server': import 'github.com/metio/kurly/workloads/netbox/server.libsonnet',
  'netbox/worker': import 'github.com/metio/kurly/workloads/netbox/worker.libsonnet',
  'mailu/front': import 'github.com/metio/kurly/workloads/mailu/front.libsonnet',
  'mailu/admin': import 'github.com/metio/kurly/workloads/mailu/admin.libsonnet',
  'mailu/imap': import 'github.com/metio/kurly/workloads/mailu/imap.libsonnet',
  'mailu/smtp': import 'github.com/metio/kurly/workloads/mailu/smtp.libsonnet',
  'mailu/antispam': import 'github.com/metio/kurly/workloads/mailu/antispam.libsonnet',
  'mailu/webmail': import 'github.com/metio/kurly/workloads/mailu/webmail.libsonnet',
  'uptime-kuma/server': import 'github.com/metio/kurly/workloads/uptime-kuma/server.libsonnet',
  'actualbudget/server': import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet',
  'homebox/server': import 'github.com/metio/kurly/workloads/homebox/server.libsonnet',
  'expenseowl/server': import 'github.com/metio/kurly/workloads/expenseowl/server.libsonnet',
  'radicale/server': import 'github.com/metio/kurly/workloads/radicale/server.libsonnet',
  'znc/server': import 'github.com/metio/kurly/workloads/znc/server.libsonnet',
  'kanboard/server': import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet',
  'paisa/server': import 'github.com/metio/kurly/workloads/paisa/server.libsonnet',
  'cryptpad/server': import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet',
  'baikal/server': import 'github.com/metio/kurly/workloads/baikal/server.libsonnet',
  'passwordpusher/server': import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet',
  'inspircd/server': import 'github.com/metio/kurly/workloads/inspircd/server.libsonnet',
  'ejabberd/server': import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet',
  'seatsurfing/server': import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet',
  'endurain/server': import 'github.com/metio/kurly/workloads/endurain/server.libsonnet',
  'wger/server': import 'github.com/metio/kurly/workloads/wger/server.libsonnet',
  'paperless-ngx/server': import 'github.com/metio/kurly/workloads/paperless-ngx/server.libsonnet',
  'invoiceninja/server': import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet',
  'mautic/server': import 'github.com/metio/kurly/workloads/mautic/server.libsonnet',
  'maybe/server': import 'github.com/metio/kurly/workloads/maybe/server.libsonnet',
  'peertube/server': import 'github.com/metio/kurly/workloads/peertube/server.libsonnet',
  'sonarqube/server': import 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet',
  'twenty/server': import 'github.com/metio/kurly/workloads/twenty/server.libsonnet',
  'twenty/worker': import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet',
  'bigcapital/server': import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet',
  'bigcapital/webapp': import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet',
  'bigcapital/gateway': import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet',
  'overleaf/server': import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet',
  'memos/server': import 'github.com/metio/kurly/workloads/memos/server.libsonnet',
  'ntfy/server': import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet',
  'gotify/server': import 'github.com/metio/kurly/workloads/gotify/server.libsonnet',
  'linkding/server': import 'github.com/metio/kurly/workloads/linkding/server.libsonnet',
  'shiori/server': import 'github.com/metio/kurly/workloads/shiori/server.libsonnet',
  'readeck/server': import 'github.com/metio/kurly/workloads/readeck/server.libsonnet',
  'dokuwiki/server': import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet',
  'excalidraw/server': import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet',
  'homer/server': import 'github.com/metio/kurly/workloads/homer/server.libsonnet',
  'dashy/server': import 'github.com/metio/kurly/workloads/dashy/server.libsonnet',
  'stirling-pdf/server': import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet',
  'microbin/server': import 'github.com/metio/kurly/workloads/microbin/server.libsonnet',
  'komga/server': import 'github.com/metio/kurly/workloads/komga/server.libsonnet',
  'kavita/server': import 'github.com/metio/kurly/workloads/kavita/server.libsonnet',
  'status-responder/responder': import 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet',
  'cnpg-cluster/cluster': import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet',
  'cnpg-image-catalog/namespaced': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet',
  'cnpg-image-catalog/cluster': import 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet',
  'dragonfly/instance': import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet',
  'otel-collector/agent': import 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet',
  'blackbox-exporter/server': import 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet',
  'alertmanager/server': import 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet',
  'keycloak/server': import 'github.com/metio/kurly/workloads/keycloak/server.libsonnet',
  'thanos/query': import 'github.com/metio/kurly/workloads/thanos/query.libsonnet',
  'thanos/store': import 'github.com/metio/kurly/workloads/thanos/store.libsonnet',
  'thanos/compact': import 'github.com/metio/kurly/workloads/thanos/compact.libsonnet',
  'thanos/receive': import 'github.com/metio/kurly/workloads/thanos/receive.libsonnet',
  'thanos/query-frontend': import 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet',
  'thanos/ruler': import 'github.com/metio/kurly/workloads/thanos/ruler.libsonnet',
  'loki/server': import 'github.com/metio/kurly/workloads/loki/server.libsonnet',
  'tempo/server': import 'github.com/metio/kurly/workloads/tempo/server.libsonnet',
  'grafana/server': import 'github.com/metio/kurly/workloads/grafana/server.libsonnet',
  'prometheus/server': import 'github.com/metio/kurly/workloads/prometheus/server.libsonnet',
  'opencost/server': import 'github.com/metio/kurly/workloads/opencost/server.libsonnet',
  'metrics-server/server': import 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet',
  'seaweedfs/server': import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet',
  'seaweedfs/master': import 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet',
  'seaweedfs/volume': import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet',
  'seaweedfs/filer': import 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet',
  'memcached/cache': import 'github.com/metio/kurly/workloads/memcached/cache.libsonnet',
  'valkey/instance': import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet',
  'valkey/cache': import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet',
};

// Fails if the annotated names and the exported names are not the same set,
// naming exactly which side is out of step.
local reconcile(section, annotated, exported) =
  local a = std.set(annotated);
  local e = std.set(exported);
  local unannotated = [name for name in e if !std.member(a, name)];
  local stale = [name for name in a if !std.member(e, name)];
  assert unannotated == [] :
         section + ': exported but not annotated in annotations.libsonnet: ' + std.join(', ', unannotated);
  assert stale == [] :
         section + ': annotated but not exported (stale annotation): ' + std.join(', ', stale);
  true;

// One catalog entry per annotated field, id-keyed and sorted for a stable diff.
local entries(section) = [
  { id: name } + section[name]
  for name in std.objectFields(section)
];

// Flattens the annotated workloads into catalog entries, checking every stage
// against stageImports: the annotated stage keys and the imported stage keys
// must be the same set, and each import must resolve to a function.
local stageKeys = std.set([
  workload + '/' + stage
  for workload in std.objectFields(ann.workloads)
  for stage in std.objectFields(ann.workloads[workload].stages)
]);
local workloadEntries =
  assert reconcile('workload stages', stageKeys, std.objectFields(stageImports));
  assert std.all([
    std.isFunction(stageImports[key])
    for key in std.objectFields(stageImports)
  ]) : 'workloads: every stage import must resolve to a function(params) app';
  [
    {
      id: workload,
      summary: ann.workloads[workload].summary,
      stages: [
        { id: stage } + ann.workloads[workload].stages[stage]
        for stage in std.objectFields(ann.workloads[workload].stages)
      ],
    }
    for workload in std.objectFields(ann.workloads)
  ];

{
  // Drift gates — object-level asserts fire when this object is manifested.
  assert reconcile('features', std.objectFields(ann.features), std.objectFieldsAll(features)),
  assert reconcile('expose', std.objectFields(ann.expose), std.objectFieldsAll(expose)),
  assert reconcile('security', std.objectFields(ann.security), std.objectFieldsAll(security)),
  assert reconcile('migrations', std.objectFields(ann.migrations), std.objectFieldsAll(migrations)),
  // Kinds live in separate files; assert the annotated set is exactly the four
  // main exposes as callables.
  assert reconcile('kinds', std.objectFields(ann.kinds), ['http', 'worker', 'cron', 'daemon', 'stateful', 'job']),
  assert std.all([std.objectHasAll(main, kind) for kind in std.objectFields(ann.kinds)]) :
         'kinds: main.libsonnet must expose every annotated kind',
  // Helpers are top-level fields of main alongside the kinds; assert the
  // annotated set is exactly the rendering terminals main exposes.
  assert reconcile('helpers', std.objectFields(ann.helpers), ['certificate', 'externalSecret', 'join', 'list', 'listOf', 'mirror']),
  assert std.all([std.objectHasAll(main, helper) for helper in std.objectFields(ann.helpers)]) :
         'helpers: main.libsonnet must expose every annotated helper',

  schemaVersion: 1,
  workloads: workloadEntries,
  kinds: entries(ann.kinds),
  features: entries(ann.features),
  expose: entries(ann.expose),
  security: entries(ann.security),
  helpers: entries(ann.helpers),
  migrations: entries(ann.migrations),
}
