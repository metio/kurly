// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// grafana — a Grafana instance as a grafana-operator `Grafana` custom resource,
// with a Prometheus `GrafanaDatasource` wired in by default. Like cnpg-cluster
// and prometheus, this authors CRs directly (rather than composing a kurly base
// kind): the grafana-operator reconciles them into the Deployment, Service, and
// ServiceAccount, and imports the datasource into the running Grafana. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local grafana = import 'github.com/metio/kurly/workloads/grafana/server.libsonnet';
//   kurly.list(grafana(prometheusUrl='http://prometheus-operated.monitoring.svc:9090'))
//
// PREREQUISITE: the grafana-operator (its CRDs and controller) must be installed.
//
// It pairs with the kurly prometheus workload: the default datasource points at
// that Prometheus's `prometheus-operated` Service, so metrics show up with no
// extra wiring. The operator generates a random admin password into the Secret
// `<name>-admin-credentials`.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

// grafana.ini, as the operator takes it: sections of string-valued keys. The
// defaults turn off the phone-home and update-check traffic a server has no
// business making; the consumer's `config` merges over them.
local baseConfig = {
  analytics: {
    reporting_enabled: 'false',
    check_for_updates: 'false',
    check_for_plugin_updates: 'false',
    feedback_links_enabled: 'false',
  },
  security: { disable_gravatar: 'true' },
  news: { news_feed_enabled: 'false' },
  log: { mode: 'console', level: 'warn' },
};

function(
  name='grafana',
  image='docker.io/grafana/grafana:12.4.5',
  replicas=1,
  config={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  // A Prometheus datasource, on by default — the point of the o11y pairing. The
  // URL defaults to the kurly prometheus workload's endpoint in the same
  // namespace; set prometheusDatasource=false to author none.
  prometheusDatasource=true,
  prometheusUrl='http://prometheus-operated:9090',
  labels={},
  annotations={},
  // Extra Grafana spec fields, merged over the below (ingress, route, an explicit
  // persistentVolumeClaim, …). The operator's schema is deep; kurly does not model
  // it, the same as cnpg's `backup` and prometheus's `spec`.
  spec={},
)
  // The image is pinned under the deployment container (so kurly.mirror can
  // redirect it and the tag is explicit); version tells the operator which
  // Grafana it is.
  local imageTag = std.split(image, ':')[1];
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as
    // cnpg-cluster and prometheus.
    assert !std.objectHasAll(self, 'config') :
           "grafana: kurly features do not apply to a custom resource — use this workload's own parameters (config, resources, labels/annotations, prometheusUrl) instead.",

    grafana: {
      apiVersion: 'grafana.integreatly.org/v1beta1',
      kind: 'Grafana',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
        version: imageTag,
        config: baseConfig + config,
        deployment: {
          spec: {
            replicas: replicas,
            template: {
              spec: {
                // Grafana never talks to the apiserver; do not mount a token.
                automountServiceAccountToken: false,
                // The pod-level hardening kurly applies everywhere. Grafana runs
                // as uid 472; the operator manages the container securityContext
                // and the writable data volume.
                securityContext: {
                  runAsNonRoot: true,
                  runAsUser: 472,
                  runAsGroup: 472,
                  fsGroup: 472,
                  seccompProfile: { type: 'RuntimeDefault' },
                },
                containers: [{
                  name: 'grafana',
                  image: image,
                  resources: resources,
                }],
              },
            },
          },
        },
      } + spec,
    },
  } + (
    if !prometheusDatasource then {} else {
      // The operator matches a datasource to an instance by label; select this
      // Grafana, and it imports Prometheus as the default datasource.
      prometheusDatasource: {
        apiVersion: 'grafana.integreatly.org/v1beta1',
        kind: 'GrafanaDatasource',
        metadata: { name: name + '-prometheus', labels: labelsFor(name) },
        spec: {
          instanceSelector: { matchLabels: { 'app.kubernetes.io/name': name } },
          datasource: {
            name: 'Prometheus',
            type: 'prometheus',
            access: 'proxy',
            url: prometheusUrl,
            isDefault: true,
          },
        },
      },
    }
  )
