// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// matrix-alertmanager-receiver — the webhook receiver an Alertmanager posts to,
// which forwards each alert into a Matrix room. A plain composable kurly.http
// workload on the official image. Import it and render with kurly.list:
//
//   local receiver = import 'github.com/metio/kurly/workloads/matrix-alertmanager-receiver/server.libsonnet';
//   kurly.list(receiver(
//     homeserverUrl='https://matrix.example.com',
//     userId='@alerts:matrix.example.com',
//     roomMapping={ pager: '!qohfwef7qwerf:example.com' },
//   ))
//
// Alertmanager then posts to http://<name>:12345/alerts/pager. Nothing outside
// the cluster needs to reach it, so an exposure is optional — compose one only
// if an Alertmanager elsewhere has to reach it.
//
// THE ACCESS TOKEN IS NOT WRITTEN INTO THE CONFIGURATION. The service expands
// environment variables in its config file, so the rendered file says
// ${MATRIX_ACCESS_TOKEN} and the value arrives from a Secret through envFrom —
// a ConfigMap is world-readable to anything with get on the namespace, and a
// Matrix access token is a full credential for the account that posts.
//
// The same mechanism carries the optional basic-auth password, which is what an
// Alertmanager outside the cluster should be made to send.
//
// Stateless: alerts are forwarded as they arrive and nothing is kept, so no
// PersistentVolume and no reason to hold it to one replica.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='matrix-alertmanager-receiver',
  image=defaultImage,
  replicas=2,
  port=12345,
  // The homeserver the posting account lives on, and that account's id. Both
  // are deployment-specific and neither has a sensible default — a placeholder
  // would authenticate against nothing.
  homeserverUrl=null,
  userId=null,
  // Short names for room ids, so an Alertmanager configuration reads
  // /alerts/pager rather than /alerts/!qohfwef7qwerf:example.com. Optional: a
  // room id works in the URL directly.
  roomMapping={},
  // The URL path an Alertmanager posts to, and where metrics are served.
  alertsPathPrefix='/alerts',
  metricsPath='/metrics',
  metricsEnabled=true,
  // Basic auth on the alerts endpoint. The username is not a secret; the
  // password comes from the Secret as BASIC_PASSWORD and is only required when
  // basicAuth is on.
  basicAuth=false,
  basicUsername='alertmanager',
  // Rewrites for an Alertmanager or Prometheus that reports a URL nobody outside
  // the cluster can follow — the in-cluster address it knows itself by, mapped
  // to the one a person clicking the alert can reach.
  externalUrlMapping={},
  generatorUrlMapping={},
  // THE SERVICE HAS NO BUILT-IN TEMPLATE and refuses to start without one for
  // firing alerts, so a default is carried here rather than left null: how an
  // alert is worded is a message format, not a fact about somebody's cluster,
  // and a workload that cannot start until the caller writes Go template markup
  // is one nobody deploys. This is upstream's own example, which colours by
  // severity and links the runbook, dashboard and silence URLs. Replace it
  // wholesale to say something else.
  firingTemplate=|||
    <p>
      {{ $color := "yellow" }}
      {{ if eq .Alert.Labels.severity "warning" }}{{ $color = "orange" }}
      {{ else if eq .Alert.Labels.severity "critical" }}{{ $color = "red" }}{{ end }}
      {{ if eq .Alert.Status "resolved" }}{{ $color = "green" }}{{ end }}
      <strong><font color="{{ $color }}">{{ .Alert.Status | ToUpper }}</font></strong>
      {{ if .Alert.Labels.name }}{{ .Alert.Labels.name }}
      {{ else if .Alert.Labels.alertname }}{{ .Alert.Labels.alertname }}{{ end }}
      &gt;&gt;
      {{ if .Alert.Labels.severity }}{{ .Alert.Labels.severity | ToUpper }}: {{ end }}
      {{ if .Alert.Annotations.description }}{{ .Alert.Annotations.description }}
      {{ else if .Alert.Annotations.summary }}{{ .Alert.Annotations.summary }}{{ end }}
      {{ if .Alert.Annotations.runbook }} | <a href="{{ .Alert.Annotations.runbook }}">Runbook</a>{{ end }}
      {{ if .Alert.Annotations.dashboard }} | <a href="{{ .Alert.Annotations.dashboard }}">Dashboard</a>{{ end }}
      | <a href="{{ .SilenceURL }}">Silence</a>
    </p>
  |||,
  // Unset, a resolved alert is rendered with the firing template, which already
  // colours a resolved status green.
  resolvedTemplate=null,
  computedValues={},
  logLevel='info',
  // The Secret holding MATRIX_ACCESS_TOKEN, and BASIC_PASSWORD when basicAuth is
  // on. kurly authors no Secret.
  secretName='matrix-alertmanager-receiver',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  // Rendered as data rather than a here-document so a caller's mappings and
  // templates cannot break the file's syntax.
  local config = {
    http: {
      // Left unset the service binds every interface, which is what a Service
      // in front of it needs; naming 127.0.0.1 here would make it unreachable.
      port: port,
      'alerts-path-prefix': alertsPathPrefix,
      'metrics-path': metricsPath,
      'metrics-enabled': metricsEnabled,
    } + (
      if !basicAuth then {} else {
        'basic-username': basicUsername,
        // Expanded from the environment at startup, so the password is never in
        // the ConfigMap.
        'basic-password': '${BASIC_PASSWORD}',
      }
    ),
    matrix: {
      'access-token': '${MATRIX_ACCESS_TOKEN}',
    } + (if homeserverUrl == null then {} else { 'homeserver-url': homeserverUrl })
      + (if userId == null then {} else { 'user-id': userId })
      + (if roomMapping == {} then {} else { 'room-mapping': roomMapping }),
    templating: (if externalUrlMapping == {} then {} else { 'external-url-mapping': externalUrlMapping })
                + (if generatorUrlMapping == {} then {} else { 'generator-url-mapping': generatorUrlMapping })
                + (if computedValues == {} then {} else { 'computed-values': computedValues })
                + (if firingTemplate == null then {} else { 'firing-template': firingTemplate })
                + (if resolvedTemplate == null then {} else { 'resolved-template': resolvedTemplate }),
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  // The image's entrypoint takes the path rather than reading a fixed location.
  + kurly.args(['--config-path', '/etc/matrix-alertmanager-receiver/config.yaml', '--log-level', logLevel])
  + kurly.config(
    { 'config.yaml': std.manifestYamlDoc(config) },
    mountPath='/etc/matrix-alertmanager-receiver',
  )
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  // A single static Go binary that writes nowhere and binds an unprivileged
  // port: the hardened default needs no relaxation at all.
  + kurly.runAs(1000, gid=1000)
  // THE METRICS PATH, NOT THE SOCKET, when metrics are on. The process binds
  // its listener BEFORE it configures handlers, so a connection probe reports
  // Ready during a window in which every request still fails — and a Service
  // sends a real Alertmanager straight into it. The metrics endpoint answers
  // only once the handlers exist, and basic auth guards the alerts endpoint
  // rather than this one, so it stays reachable to the kubelet.
  //
  // With metrics off there is no unguarded path left to ask, and the connection
  // probe is the honest fallback rather than a probe against a route that would
  // read an authentication failure as ill health.
  + (
    local check = if metricsEnabled then { httpGet: { path: metricsPath, port: 'http' } }
    else { tcpSocket: { port: 'http' } };
    kurly.readinessProbe(check) + kurly.livenessProbe(check)
  )
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
