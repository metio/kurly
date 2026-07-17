// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cnpg-image-catalog/namespaced — the PostgreSQL images a namespace's
// CloudNativePG clusters may run, as an `ImageCatalog` custom resource. One
// catalog lists one image per major version; a cnpg-cluster pins a major via
// spec.imageCatalogRef and the catalog owns the patch. That split is the point:
// a patch bump is one line here and rolls every cluster on that major, while a
// major upgrade stays a deliberate, per-cluster change.
//
//   local catalog = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet';
//   kurly.list(catalog(name='postgres', images={
//     '16': 'ghcr.io/cloudnative-pg/postgresql:16.6',
//     '17': 'ghcr.io/cloudnative-pg/postgresql:17.2',
//   }))
//
// This catalog is owned by the team that owns the databases and needs no
// cluster-scoped RBAC to deploy. For one catalog serving every namespace, use
// the cluster stage instead — same spec, cluster-scoped kind.
//
// Bumping an image here rolls EVERY cluster referencing that major, with no
// change to any Cluster CR — that blast radius is the feature, and the reason a
// catalog is worth having, but it is a fleet-wide event: stage it the way you
// would any other rollout.
//
// PREREQUISITE: the CloudNativePG operator must be installed in the cluster.
local version = std.rstripChars(importstr './version.txt', '\n');

// The kurly label convention, applied to the CR so the same ownership marker and
// version stamp ride on it as on every other kurly manifest.
local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='postgres',
  images={ '17': 'ghcr.io/cloudnative-pg/postgresql:17.2' },
  componentImages={},
  labels={},
  annotations={},
)
  // An empty catalog is always a mistake: a Cluster referencing it cannot
  // resolve an image for its major and the operator leaves it unreconciled.
  assert images != {} :
         'cnpg-image-catalog: images must list at least one major -> image entry';
  // CNPG keys catalog entries by an integer major and requires it to be unique.
  // Jsonnet object keys are strings, so each must parse as an integer — a typo
  // like '17.2' names a patch, not a major, and would silently never match a
  // Cluster's imageCatalogRef.major.
  assert std.all([
    std.length(std.findSubstr('.', major)) == 0 && std.parseInt(major) > 0
    for major in std.objectFields(images)
  ]) : 'cnpg-image-catalog: every images key must be a PostgreSQL major version number, e.g. 17';
  {

    // A kurly feature composed onto this workload cannot work, and the failure is
    // invisible: features contribute to a hidden `config` that a BASE KIND reads
    // when it computes its manifests, and this workload has no base — it authors
    // a custom resource whose pods belong to an operator. So
    // `cnpg-image-catalog() + kurly.podLabels({…})` renders cleanly, exit 0, and the labels
    // are simply gone. That is the worst outcome available: a clean render and a
    // cluster that behaves differently than the source says.
    //
    // The presence of `config` is exactly the fingerprint of a composed feature,
    // so the render fails and names the parameters that do work. The raw `+`
    // escape hatch still patches the resource itself, since that touches no
    // config.
    assert !std.objectHasAll(self, 'config') :
           'cnpg-image-catalog: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, images), which are wired to the fields the operator honours.",
    catalog: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'ImageCatalog',
      // A catalog generates no pods, so there is no pod metadata to inherit —
      // these land on the object itself, for whatever selects or annotates it.
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        // Sorted by major so the rendered catalog diffs stably as entries come
        // and go.
        images: [
          { major: std.parseInt(major), image: images[major] }
          for major in std.sort(std.objectFields(images), keyF=std.parseInt)
        ],
        // Sidecar/component image overrides, keyed by component name. Rarely
        // set; pruned away when empty.
        componentImages: (
          if componentImages == {} then null
          else [
            { key: key, image: componentImages[key] }
            for key in std.sort(std.objectFields(componentImages))
          ]
        ),
      }),
    },
  }
