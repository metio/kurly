// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// llmkube — the LLMKube controller manager: a Kubernetes operator that runs
// self-hosted language-model inference from custom resources (Model,
// InferenceService, ModelRouter, LoRAAdapter, …), scheduling the serving pods,
// downloading model weights into a cache volume and exposing an OpenAI-compatible
// API. A plain composable kurly.http workload — the operator itself, not one of
// the resources it reconciles — that carries the cluster RBAC a controller needs,
// so it ships a ServiceAccount, a ClusterRole/Binding, and the namespaced
// leader-election Role/Binding alongside its Deployment and Service.
//
//   local llmkube = import 'github.com/metio/kurly/workloads/llmkube/controller.libsonnet';
//   kurly.list(llmkube(namespace='llmkube-system'))
//
// The CRDs are NOT part of this workload — controller-runtime watches the kinds
// at start-up, so apply the upstream CRDs from the release matching the pinned
// image BEFORE this, or the manager exits before it ever becomes ready.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './controller.image', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'kurly.metio.wtf/version': version,
};

// What the controller reconciles, in the upstream operator's own terms: its own
// custom resources, the Deployments/Services/PVCs/Jobs it creates for an
// inference service, and read access to the nodes and scheduling objects it
// places those pods against. The optional integrations (Envoy AI Gateway,
// Grafana, Pyrra) are granted too, because the manager watches them where the
// CRDs exist and is silent where they do not.
local controllerRules = [
  { apiGroups: [''], resources: ['configmaps', 'services'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: [''], resources: ['namespaces', 'nodes', 'pods', 'secrets'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: [''], resources: ['persistentvolumeclaims'], verbs: ['create', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: [''], resources: ['pods/eviction'], verbs: ['create'] },
  { apiGroups: ['', 'events.k8s.io'], resources: ['events'], verbs: ['create', 'patch'] },
  { apiGroups: ['apps'], resources: ['deployments'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['autoscaling'], resources: ['horizontalpodautoscalers'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['batch'], resources: ['jobs'], verbs: ['create', 'delete', 'get', 'list', 'watch'] },
  { apiGroups: ['discovery.k8s.io'], resources: ['endpointslices'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['resource.k8s.io'], resources: ['resourceclaims', 'resourceclaimtemplates'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['scheduling.k8s.io'], resources: ['priorityclasses'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['inference.llmkube.dev'], resources: ['inferenceservices', 'loraadapters', 'modelrouters', 'models'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['inference.llmkube.dev'], resources: ['gpuquotas'], verbs: ['get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['inference.llmkube.dev'], resources: ['gpuquotas/status', 'inferenceservices/status', 'loraadapters/status', 'modelrouters/status', 'models/status'], verbs: ['get', 'patch', 'update'] },
  { apiGroups: ['inference.llmkube.dev'], resources: ['inferenceservices/finalizers', 'loraadapters/finalizers', 'modelrouters/finalizers', 'models/finalizers'], verbs: ['update'] },
  { apiGroups: ['federation.llmkube.dev'], resources: ['federatedclusters'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['federation.llmkube.dev'], resources: ['federatedclusters/status'], verbs: ['get', 'patch', 'update'] },
  { apiGroups: ['foreman.llmkube.dev'], resources: ['agentictasks', 'agents', 'fleetnodes', 'workloads'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['foreman.llmkube.dev'], resources: ['agentreleases'], verbs: ['get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['foreman.llmkube.dev'], resources: ['modelprofiles'], verbs: ['get', 'list', 'watch'] },
  { apiGroups: ['foreman.llmkube.dev'], resources: ['agentictasks/status', 'agentreleases/status', 'agents/status', 'fleetnodes/status', 'workloads/status'], verbs: ['get', 'patch', 'update'] },
  { apiGroups: ['foreman.llmkube.dev'], resources: ['agentictasks/finalizers', 'agentreleases/finalizers', 'agents/finalizers', 'fleetnodes/finalizers', 'workloads/finalizers'], verbs: ['update'] },
  { apiGroups: ['aigateway.envoyproxy.io'], resources: ['aigatewayroutes', 'aiservicebackends'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['gateway.envoyproxy.io'], resources: ['backends', 'backendtrafficpolicies', 'securitypolicies'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  { apiGroups: ['grafana.integreatly.org'], resources: ['grafanadashboards'], verbs: ['create', 'delete', 'get', 'update'] },
  { apiGroups: ['pyrra.dev'], resources: ['servicelevelobjectives'], verbs: ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'] },
  // The protected metrics endpoint authenticates and authorizes every scrape
  // against the API server, so the manager reviews the caller's token itself.
  { apiGroups: ['authentication.k8s.io'], resources: ['tokenreviews'], verbs: ['create'] },
  { apiGroups: ['authorization.k8s.io'], resources: ['subjectaccessreviews'], verbs: ['create'] },
];

// Leader election is namespaced: the Lease lives beside the manager.
local leaderElectionRules = [
  { apiGroups: [''], resources: ['configmaps'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'] },
  { apiGroups: ['coordination.k8s.io'], resources: ['leases'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'] },
  { apiGroups: [''], resources: ['events'], verbs: ['create', 'patch'] },
];

function(
  name='llmkube',
  // Where the controller runs. It names the ServiceAccount in the
  // ClusterRoleBinding — a cluster-scoped object that cannot inherit a namespace
  // later — so it MUST match the namespace you deploy to.
  namespace='llmkube-system',
  image=defaultImage,
  replicas=1,
  // Leader election keeps a second replica idle instead of reconciling the same
  // resources twice. Leave it on even at one replica: it also stops an overlapping
  // rollout from running two managers.
  leaderElect=true,
  resources={ requests: { cpu: '10m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  env={},
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  assert namespace != null :
         'llmkube: namespace is required — the ClusterRoleBinding must name the ServiceAccount by namespace, which a cluster-scoped object cannot inherit later.';

  local args =
    [
      '--health-probe-bind-address=:8081',
      '--metrics-bind-address=:8443',
      '--metrics-secure=true',
    ]
    + (if leaderElect then ['--leader-elect'] else []);

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The Service publishes the protected metrics endpoint; the probe port stays on
  // the pod, since nothing outside the kubelet reads /healthz.
  + kurly.port(8443)
  + kurly.servicePort(8443)
  + kurly.extraPort('health', 8081, expose=false)
  + kurly.args(args)
  + kurly.env(env)
  // The distroless image already runs as 65532; pinning it keeps the restricted
  // posture verifiable without resolving a user out of the image.
  + kurly.runAs(65532)
  // The read-only root filesystem stands: the manager writes its self-signed
  // metrics serving certificate under /tmp, and stages a locally sourced model
  // file through /models while validating it. Both are per-pod scratch — the model
  // cache the inference pods read is a PVC the controller provisions at reconcile
  // time, not a volume of its own.
  + kurly.scratch('/tmp', '64Mi')
  + kurly.scratch('/models', '1Gi')
  // A Service named after the workload would inject LLMKUBE_PORT as a tcp:// URL
  // into every container in the namespace, including the inference pods it starts.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/readyz', port: 'health' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'health' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
  + {
    // Run under a dedicated ServiceAccount (kurly mounts its token) and author the
    // RBAC as owned manifests — the http kind mints only namespaced RBAC, while a
    // controller reconciles its custom resources in every namespace.
    config+:: { serviceAccountName: name },

    // The operator is a fixed part of the cluster rather than a tenant workload:
    // its ServiceAccount and the ClusterRoleBinding naming it as a subject state
    // one namespace, so the Deployment and Service state the same one.
    deployment+: { metadata+: { namespace: namespace } },
    service+: { metadata+: { namespace: namespace } },

    ownedManifests+: [
      {
        apiVersion: 'v1',
        kind: 'ServiceAccount',
        metadata: { name: name, namespace: namespace, labels: labelsFor(name) },
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRole',
        metadata: { name: name, labels: labelsFor(name) },
        rules: controllerRules,
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRoleBinding',
        metadata: { name: name, labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: name },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'Role',
        metadata: { name: name + '-leader-election', namespace: namespace, labels: labelsFor(name) },
        rules: leaderElectionRules,
      },
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'RoleBinding',
        metadata: { name: name + '-leader-election', namespace: namespace, labels: labelsFor(name) },
        roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: name + '-leader-election' },
        subjects: [{ kind: 'ServiceAccount', name: name, namespace: namespace }],
      },
    ],
  }
