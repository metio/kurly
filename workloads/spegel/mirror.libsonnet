// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// spegel — a stateless, cluster-local OCI registry mirror (https://spegel.dev). It
// runs one pod on every node (a DaemonSet) that serves image layers already present
// in the node's containerd content store to its peers, so a pull satisfied by any
// node in the cluster never leaves it. Nodes discover each other over a peer-to-peer
// router; an init container writes containerd's registry-mirror config so the kubelet
// pulls through the local Spegel first.
//
// This is genuinely node-level infrastructure, so — like the database clusters — it
// authors its manifests directly rather than composing a kurly base kind: it needs an
// init container, hostPath access to the containerd socket and content store, a
// NodePort the kubelet reaches the mirror on, and a headless Service the peers bootstrap
// against. None of that fits the http/worker/daemon composable shape. Import it, adapt
// with the parameters below, and render with kurly.list:
//
//   local spegel = import 'github.com/metio/kurly/workloads/spegel/mirror.libsonnet';
//   kurly.list(spegel(namespace='spegel'))
//
// NAMESPACE IS LOAD-BEARING: peers bootstrap via the DNS name of the headless Service,
// whose FQDN embeds the namespace — so `namespace` MUST match where you deploy, and
// every object is stamped with it.
//
// SECURITY: the mirror runs as root with hostPath mounts (the containerd socket is
// root-owned) — the restricted Pod Security Standard cannot admit it. The posture is
// hardened as far as the job allows (read-only root filesystem, no privilege
// escalation, all capabilities dropped, RuntimeDefault seccomp), but this is
// privileged node infrastructure and should be deployed to a namespace labelled for
// it. The socket is mounted read-only; the content store is mounted read-only.
local version = std.rstripChars(importstr './version.txt', '\n');

// The kurly label convention, applied to every object so the same ownership marker and
// version stamp ride on the mirror as on every other kurly manifest.
local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='spegel',
  // Where Spegel runs. The peer-bootstrap DNS name embeds this namespace, so it MUST
  // match the namespace you deploy to; every object below is stamped with it.
  namespace='spegel',
  image='ghcr.io/spegel-org/spegel:v0.7.4',
  // The node's containerd socket and stores. Defaults match a stock containerd; a
  // cluster with a relocated socket or content path (k3s, some managed distros) must
  // point these at the real locations or the mirror serves nothing.
  containerdSock='/run/containerd/containerd.sock',
  containerdContentPath='/var/lib/containerd/io.containerd.content.v1.content',
  containerdRegistryConfigPath='/etc/containerd/certs.d',
  containerdNamespace='k8s.io',
  // The kubelet reaches the local mirror at http://<node-ip>:registryNodePort, which
  // the init container writes into containerd's mirror config; the NodePort Service
  // routes it to the registry port. Keep the two in step with the cluster's NodePort
  // range.
  registryPort=5000,
  registryNodePort=30020,
  routerPort=5001,
  metricsPort=9090,
  logLevel='INFO',
  resolveTags=true,
  mirrorResolveRetries=3,
  mirrorResolveTimeout='20ms',
  clusterDomain='cluster.local',
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '128Mi' } },
  // DaemonSets usually run everywhere, control-plane nodes included, so a mirror is
  // present wherever an image is pulled. Override to confine it.
  tolerations=[{ operator: 'Exists' }],
  nodeSelector={},
  affinity=null,
  priorityClassName=null,
  labels={},
  annotations={},
)
  assert namespace != null :
         'spegel: namespace is required — the peer-bootstrap DNS name embeds it and every object is stamped with it.';

  // The selector keys on the stable identity label alone: pod-template and metadata
  // labels may carry a consumer's extras, but the DaemonSet selector is immutable, so
  // nothing volatile may reach it.
  local selectorLabels = { 'app.kubernetes.io/name': name };
  local podLabels = labelsFor(name) + labels;

  // Root-owned socket access rules out running non-root; the rest of the posture is
  // hardened as far as that allows.
  local securityContext = {
    readOnlyRootFilesystem: true,
    allowPrivilegeEscalation: false,
    capabilities: { drop: ['ALL'] },
    seccompProfile: { type: 'RuntimeDefault' },
  };

  local nodeIp = { name: 'NODE_IP', valueFrom: { fieldRef: { fieldPath: 'status.hostIP' } } };

  local bootstrapDomain = name + '-bootstrap.' + namespace + '.svc.' + clusterDomain;

  // Writes containerd's registry-mirror hosts.toml so the kubelet pulls through the
  // local Spegel (http://<node-ip>:registryNodePort) before the upstream registry.
  local configurationContainer = {
    name: 'configuration',
    image: image,
    securityContext: securityContext,
    args: [
      'configuration',
      '--log-level=' + logLevel,
      '--containerd-registry-config-path=' + containerdRegistryConfigPath,
      '--mirror-targets',
      'http://$(NODE_IP):' + registryNodePort,
      '--resolve-tags=' + resolveTags,
      '--prepend-existing=false',
    ],
    env: [nodeIp],
    volumeMounts: [{ name: 'containerd-config', mountPath: containerdRegistryConfigPath }],
  };

  local registryContainer = {
    name: 'registry',
    image: image,
    securityContext: securityContext,
    args: [
      'registry',
      '--log-level=' + logLevel,
      '--mirror-resolve-retries=' + mirrorResolveRetries,
      '--mirror-resolve-timeout=' + mirrorResolveTimeout,
      '--registry-addr=:' + registryPort,
      '--router-addr=:' + routerPort,
      '--metrics-addr=:' + metricsPort,
      '--containerd-sock=' + containerdSock,
      '--containerd-namespace=' + containerdNamespace,
      '--containerd-content-path=' + containerdContentPath,
      '--bootstrap-kind=dns',
      '--dns-bootstrap-domain=' + bootstrapDomain,
    ],
    env: [
      // Ties the Go heap ceiling to the container's memory limit so a spike sheds
      // rather than getting OOMKilled.
      { name: 'GOMEMLIMIT', valueFrom: { resourceFieldRef: { resource: 'limits.memory', divisor: 1 } } },
      nodeIp,
    ],
    ports: [
      { name: 'registry', containerPort: registryPort, protocol: 'TCP' },
      { name: 'router-tcp', containerPort: routerPort, protocol: 'TCP' },
      { name: 'router-quic', containerPort: routerPort, protocol: 'UDP' },
      { name: 'metrics', containerPort: metricsPort, protocol: 'TCP' },
    ],
    // Spegel serves its health endpoints on the registry port.
    startupProbe: { httpGet: { path: '/readyz', port: 'registry' }, periodSeconds: 3, failureThreshold: 60 },
    readinessProbe: { httpGet: { path: '/readyz', port: 'registry' } },
    livenessProbe: { httpGet: { path: '/livez', port: 'registry' } },
    resources: resources,
    volumeMounts: [
      { name: 'containerd-sock', mountPath: containerdSock, readOnly: true },
      { name: 'containerd-content', mountPath: containerdContentPath, readOnly: true },
    ],
  };

  {
    // A kurly feature composed onto this workload writes a hidden `config` that no
    // base kind reads here (this authors plain manifests, not a composable base), so
    // it would render cleanly and do nothing. The presence of `config` is exactly
    // that fingerprint, so fail the render and point at the real parameters instead.
    // The raw `+` escape hatch still patches the manifests, since that touches no config.
    assert !std.objectHasAll(self, 'config') :
           'spegel: kurly features do not apply here — this workload authors plain manifests, not a composable base, so a composed feature would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, resources, tolerations, nodeSelector, affinity, the containerd paths and ports).",

    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: { name: name, namespace: namespace, labels: labelsFor(name) + labels },
      // The mirror talks to peers over DNS and to containerd over the socket, never
      // to the apiserver, so it needs no mounted token.
      automountServiceAccountToken: false,
    },

    daemonset: {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: std.prune({
        name: name,
        namespace: namespace,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
        selector: { matchLabels: selectorLabels },
        template: {
          metadata: std.prune({
            labels: podLabels,
            annotations: (if annotations == {} then null else annotations),
          }),
          spec: std.prune({
            serviceAccountName: name,
            automountServiceAccountToken: false,
            priorityClassName: priorityClassName,
            nodeSelector: (if nodeSelector == {} then null else nodeSelector),
            tolerations: (if tolerations == [] then null else tolerations),
            affinity: affinity,
            initContainers: [configurationContainer],
            containers: [registryContainer],
            volumes: [
              { name: 'containerd-sock', hostPath: { path: containerdSock, type: 'Socket' } },
              { name: 'containerd-content', hostPath: { path: containerdContentPath, type: 'Directory' } },
              { name: 'containerd-config', hostPath: { path: containerdRegistryConfigPath, type: 'DirectoryOrCreate' } },
            ],
          }),
        },
      },
    },

    // The kubelet reaches the local mirror here: NodePort registryNodePort routes to
    // the registry port on the node's own Spegel (the init container points containerd
    // at http://<node-ip>:registryNodePort).
    registryService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: name + '-registry', namespace: namespace, labels: labelsFor(name) + labels },
      spec: {
        type: 'NodePort',
        selector: selectorLabels,
        ports: [{ name: 'registry', port: registryPort, targetPort: 'registry', nodePort: registryNodePort, protocol: 'TCP' }],
      },
    },

    // Peers bootstrap the P2P router against this headless Service's DNS records;
    // publishNotReadyAddresses lets a starting node find peers before it is itself Ready.
    bootstrapService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: name + '-bootstrap', namespace: namespace, labels: labelsFor(name) + labels },
      spec: {
        clusterIP: 'None',
        publishNotReadyAddresses: true,
        selector: selectorLabels,
        ports: [
          { name: 'registry', port: registryPort, targetPort: 'registry', protocol: 'TCP' },
          { name: 'router-tcp', port: routerPort, targetPort: 'router-tcp', protocol: 'TCP' },
        ],
      },
    },

    metricsService: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: name, namespace: namespace, labels: labelsFor(name) + labels },
      spec: {
        selector: selectorLabels,
        ports: [{ name: 'metrics', port: metricsPort, targetPort: 'metrics', protocol: 'TCP' }],
      },
    },
  }
