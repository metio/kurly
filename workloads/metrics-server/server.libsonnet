// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// metrics-server — the Kubernetes Metrics Server: it scrapes resource usage (CPU,
// memory) from every node's kubelet and serves it through the aggregated
// `metrics.k8s.io` API, which is what `kubectl top` and Horizontal Pod
// Autoscalers read. A plain composable kurly.http workload, but one that
// registers an APIService and needs the aggregation RBAC, so it carries a
// ServiceAccount, ClusterRoles/Bindings, the kube-system auth-reader RoleBinding,
// and the APIService alongside its Deployment and Service. Import it and render
// with kurly.list:
//
//   local metricsServer = import 'github.com/metio/kurly/workloads/metrics-server/server.libsonnet';
//   kurly.list(metricsServer())
//
// On clusters whose kubelets serve a self-signed serving certificate (kind, many
// on-prem setups), set kubeletInsecureTLS=true or the scrape fails the TLS
// handshake.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='metrics-server',
  // Where metrics-server runs. It names the ServiceAccount the cluster RBAC and
  // the APIService reference — cluster-scoped objects that cannot inherit it
  // later — so it MUST match the namespace you deploy to. kube-system is the
  // conventional home.
  namespace='kube-system',
  image='registry.k8s.io/metrics-server/metrics-server:v0.8.1',
  replicas=1,
  // Skip verifying the kubelet's serving certificate. The default trusts the
  // cluster CA; turn this on where the kubelets present a self-signed cert (kind,
  // kubeadm without serving-cert rotation) or every scrape fails the handshake.
  kubeletInsecureTLS=false,
  metricResolution='15s',
  resources={ requests: { cpu: '100m', memory: '200Mi' }, limits: { memory: '400Mi' } },
  labels={},
  annotations={},
)
  assert namespace != null :
         'metrics-server: namespace is required — the APIService and cluster RBAC name the ServiceAccount by namespace, which cluster-scoped objects cannot inherit later.';

  local args =
    [
      '--cert-dir=/tmp',
      '--secure-port=10250',
      '--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname',
      '--kubelet-use-node-status-port',
      '--metric-resolution=' + metricResolution,
    ]
    + (if kubeletInsecureTLS then ['--kubelet-insecure-tls'] else []);

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(10250)
  // The Service the APIService routes to publishes 443 onto the secure port.
  + kurly.servicePort(443)
  + kurly.args(args)
  // The image ships no non-root user; pin one so the restricted posture admits it.
  + kurly.runAs(1000)
  // --cert-dir writes the self-signed serving cert somewhere writable; the
  // read-only root filesystem stands with a scratch /tmp for it.
  + kurly.scratch('/tmp', '64Mi')
  // The API server serves HTTPS on the secure port, so the probes speak HTTPS.
  + kurly.readinessProbe({ httpGet: { path: '/readyz', port: 'http', scheme: 'HTTPS' } })
  + kurly.livenessProbe({ httpGet: { path: '/livez', port: 'http', scheme: 'HTTPS' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + {
    config+:: { serviceAccountName: name },

    ownedManifests+: [
      {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: { name: name, namespace: namespace, labels: labelsFor(name) },
      },
      // Read node/pod metrics from the kubelets and the apiserver. Named after the
      // workload (not the conventional system:metrics-server) so it follows the
      // workload name like every other object.
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRole',
        metadata: { name: name, labels: labelsFor(name) },
        rules: [
          { apiGroups: [''], resources: ['nodes/metrics'], verbs: ['get'] },
          { apiGroups: [''], resources: ['pods', 'nodes'], verbs: ['get', 'list', 'watch'] },
        ],
      },
      // Aggregated into the built-in view/edit/admin roles by its labels, so
      // ordinary users can read the metrics API without a dedicated binding — the
      // labels do the work, so the name is free to follow the workload.
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRole',
        metadata: {
          name: name + '-aggregated-reader',
          labels: labelsFor(name) + {
            'rbac.authorization.k8s.io/aggregate-to-view': 'true',
            'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
            'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
          },
        },
        rules: [{ apiGroups: ['metrics.k8s.io'], resources: ['pods', 'nodes'], verbs: ['get', 'list', 'watch'] }],
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRoleBinding',
        metadata: { name: name, labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: name },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
      // The aggregation layer delegates authn/authz to the apiserver.
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRoleBinding',
        metadata: { name: name + ':system:auth-delegator', labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: 'system:auth-delegator' },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
      // Reads the extension-apiserver-authentication ConfigMap, which lives in
      // kube-system regardless of where metrics-server itself runs.
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'RoleBinding',
        metadata: { name: name + '-auth-reader', namespace: 'kube-system', labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: 'extension-apiserver-authentication-reader' },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
      // Registers metrics.k8s.io/v1beta1 with the aggregation layer, routed to the
      // Service. insecureSkipTLSVerify because the server uses its own self-signed
      // serving cert (from --cert-dir).
      {
        apiVersion: 'apiregistration.k8s.io/v1',
        kind: 'APIService',
        metadata: { name: 'v1beta1.metrics.k8s.io', labels: labelsFor(name) },
        spec: {
          service: { name: name, namespace: namespace, port: 443 },
          group: 'metrics.k8s.io',
          version: 'v1beta1',
          insecureSkipTLSVerify: true,
          groupPriorityMinimum: 100,
          versionPriority: 100,
        },
      },
    ],
  }
