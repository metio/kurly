// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cnpg-cluster — a highly-available PostgreSQL cluster as a CloudNativePG
// `Cluster` custom resource. PostgreSQL on Kubernetes is always run through
// CNPG here, so this workload authors the CR directly (rather than composing a
// kurly base kind); the CNPG operator reconciles it into the StatefulSet, pods,
// Services, and failover machinery. Import it, adapt with the parameters below,
// and render with kurly.list:
//
//   local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
//   kurly.list(cnpg(name='orders-db', instances=3, storageSize='20Gi'))
//
// PREREQUISITE: the CloudNativePG operator must be installed in the cluster.
local version = 'dev';

// The kurly label convention, applied to the CR so the same ownership marker and
// version stamp ride on it as on every other kurly manifest.
local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='postgres',
  instances=3,
  storageSize='10Gi',
  storageClass=null,
  walSize=null,
  walStorageClass=null,
  imageName=null,
  catalog=null,
  catalogScope='namespaced',
  major=null,
  database='app',
  owner='app',
  parameters={},
  resources=null,
  enablePodMonitor=true,
  imagePullSecrets=[],
  serviceAccountAnnotations={},
  labels={},
  annotations={},
  affinity=null,
  topologySpreadConstraints=[],
  priorityClassName=null,
  schedulerName=null,
)
  // CNPG resolves the image from exactly one source. Naming both is a config
  // error the operator rejects, so fail the render instead of the apply.
  assert !(imageName != null && catalog != null) :
         'cnpg-cluster: imageName and catalog are mutually exclusive — the image comes from one source';
  // A catalog lists one image per major, so the reference has to say which
  // major this cluster pins; without it the operator cannot resolve an image.
  assert catalog == null || major != null :
         'cnpg-cluster: catalog requires major (the PostgreSQL major version this cluster pins)';
  assert catalogScope == 'namespaced' || catalogScope == 'cluster' :
         "cnpg-cluster: catalogScope must be 'namespaced' or 'cluster', got '" + catalogScope + "'";

  // Huge pages are worth having — PostgreSQL maps shared_buffers into EVERY
  // backend, so at 4KB a large shared_buffers costs megabytes of page tables per
  // connection and thrashes the TLB — but they are also easy to ask for in a way
  // that cannot start. Both mistakes below are certain failures, so they fail the
  // render rather than a pod.
  local limits = if resources == null || !std.objectHas(resources, 'limits') then {} else resources.limits;
  local requests = if resources == null || !std.objectHas(resources, 'requests') then {} else resources.requests;
  local hugeLimits = [k for k in std.objectFields(limits) if std.startsWith(k, 'hugepages-')];
  local hugeRequests = [k for k in std.objectFields(requests) if std.startsWith(k, 'hugepages-')];

  // huge_pages=on tells PostgreSQL to refuse to start rather than fall back to
  // 4KB pages — which is the point of setting it, and why it must be paired with
  // an allocation. (The default, 'try', falls back silently: you believe you have
  // huge pages and do not.)
  assert !(std.objectHas(parameters, 'huge_pages') && parameters.huge_pages == 'on') || hugeLimits != [] :
         "cnpg-cluster: huge_pages='on' needs a hugepages-* resource limit, or PostgreSQL refuses to start. "
         + 'Add e.g. resources.limits["hugepages-2Mi"], and note the node must have them pre-allocated — '
         + 'Kubernetes only schedules against huge pages a node already reports.';

  // Kubernetes rejects the pod outright when a hugepages request and limit differ:
  // the resource is not overcommittable, so the two must match exactly.
  assert std.all([std.objectHas(requests, k) && requests[k] == limits[k] for k in hugeLimits]) :
         'cnpg-cluster: every hugepages-* request must equal its limit (Kubernetes rejects the pod otherwise). '
         + 'Limits: ' + std.toString({ [k]: limits[k] for k in hugeLimits })
         + ', requests: ' + std.toString({ [k]: requests[k] for k in hugeRequests });
  {

    // A kurly feature composed onto this workload cannot work, and the failure is
    // invisible: features contribute to a hidden `config` that a BASE KIND reads
    // when it computes its manifests, and this workload has no base — it authors
    // a custom resource whose pods belong to an operator. So
    // `cnpg-cluster() + kurly.podLabels({…})` renders cleanly, exit 0, and the labels
    // are simply gone. That is the worst outcome available: a clean render and a
    // cluster that behaves differently than the source says.
    //
    // The presence of `config` is exactly the fingerprint of a composed feature,
    // so the render fails and names the parameters that do work. The raw `+`
    // escape hatch still patches the resource itself, since that touches no
    // config.
    assert !std.objectHasAll(self, 'config') :
           'cnpg-cluster: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations for pod metadata, imagePullSecrets, resources, storageClass), which are wired to the fields the operator honours.",
    cluster: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'Cluster',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        // The pods here belong to the operator, not to kurly: there is no pod
        // template to attach metadata to, so kurly.podLabels() composed onto
        // this workload would land in a config nothing reads and vanish without
        // error. inheritedMetadata is CNPG's own answer — the operator copies it
        // onto every object it generates for this Cluster, pods included — so
        // network-policy selectors, sidecar injection and scrape hints reach the
        // PostgreSQL pods through it.
        inheritedMetadata: (
          if labels == {} && annotations == {} then null
          else std.prune({
            labels: (if labels == {} then null else labels),
            annotations: (if annotations == {} then null else annotations),
          })
        ),
        // Three instances give one primary and two hot-standby replicas. Whether
        // a node loss actually costs one of them is a scheduling question, not a
        // count: CNPG's pod anti-affinity is 'preferred' unless told otherwise,
        // so nothing stops all three landing on one node. Pass
        // affinity={ podAntiAffinityType: 'required' } to make it a rule — at
        // the price of instances staying Pending when no node satisfies it.
        instances: instances,
        // null lets the operator pick the PostgreSQL image matching its version.
        imageName: imageName,
        // Referencing a catalog moves the image choice out of this CR: the
        // catalog owns the patch for the pinned major, so a fleet-wide bump
        // never touches a Cluster. Note that the version this cluster runs then
        // no longer follows app.kubernetes.io/version — the label stamps the
        // kurly workload, not the PostgreSQL image the catalog resolves.
        imageCatalogRef: (
          if catalog == null then null else {
            apiGroup: 'postgresql.cnpg.io',
            kind: if catalogScope == 'cluster' then 'ClusterImageCatalog' else 'ImageCatalog',
            name: catalog,
            major: major,
          }
        ),
        storage: std.prune({
          size: storageSize,
          storageClass: storageClass,
        }),
        // PostgreSQL writes its WAL sequentially and its data randomly, so a
        // production cluster usually wants the WAL on its own volume — often a
        // faster class. Left unset, the WAL shares the data volume, which is
        // CNPG's default and fine for small clusters.
        walStorage: (
          if walSize == null && walStorageClass == null then null
          else std.prune({
            size: walSize,
            storageClass: walStorageClass,
          })
        ),
        // A fresh cluster is bootstrapped with an application database and owner
        // role; the operator mints the credentials as a Secret.
        bootstrap: {
          initdb: {
            database: database,
            owner: owner,
          },
        },
        // Extra postgresql.conf parameters, merged over the operator defaults.
        postgresql: (if parameters == {} then null else { parameters: parameters }),
        resources: resources,
        // A PodMonitor for the Prometheus Operator, on by default.
        monitoring: (if enablePodMonitor then { enablePodMonitor: true } else null),
        // Placement is the cluster's business — which nodes carry databases,
        // what taints keep everything else off them, which zones exist — and a
        // Cluster that cannot express it does not land on a dedicated node pool
        // at all.
        //
        // Passed VERBATIM: `affinity` here is CNPG's own schema (nodeSelector,
        // tolerations, podAntiAffinityType, topologyKey, additionalPodAffinity),
        // not Kubernetes' affinity, and kurly does not model foreign APIs — a
        // second-hand copy would drift against the operator's and lie about what
        // it accepts. See the CNPG API reference for the fields.
        affinity: affinity,
        topologySpreadConstraints: (if topologySpreadConstraints == [] then null else topologySpreadConstraints),
        priorityClassName: priorityClassName,
        schedulerName: schedulerName,
        // The operator pulls PostgreSQL itself, so the pull secrets belong to
        // the Cluster: kurly.imagePullSecrets() is a pod-level feature and there
        // is no pod here to attach it to. Without this a cluster on a private
        // registry cannot pull at all, whatever the images are pointed at.
        imagePullSecrets: (
          if imagePullSecrets == [] then null
          else [{ name: s } for s in imagePullSecrets]
        ),
        // The operator runs the cluster's pods and its backup jobs under a
        // ServiceAccount it creates itself, so kurly.serviceAccountAnnotations()
        // — a pod-level feature — cannot reach it, and there is no pod here to
        // attach one to anyway. CNPG's serviceAccountTemplate is the operator's
        // own hook: it stamps these annotations onto that account, which is how
        // a cloud IAM binding (IRSA, GKE/Azure workload identity) reaches the
        // backup path so WAL and base backups can write to object storage
        // without static keys.
        serviceAccountTemplate: (
          if serviceAccountAnnotations == {} then null
          else { metadata: { annotations: serviceAccountAnnotations } }
        ),
      }),
    },
  }
