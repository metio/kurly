// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kurly — a bookstore of Kubernetes workload recipes, written in Jsonnet on
// top of k8s-libsonnet. Start from a kind (a base "default" for that shape),
// then add capabilities as composable `+` features; the visible fields of the
// result are the manifests.
//
//   kurly.http('tik', image)                 // the base
//   + kurly.args(['backend', '--config=…'])  // features, in any order
//   + kurly.store('/var/lib/tik', '1Gi')
//   + kurly.runAs(12345)
//   + kurly.expose.gateway(host, 'shared')   // exposure & security are features too
//
// A feature only ever contributes to the hidden `config`, so the manifests
// late-bind against the merged config regardless of compose order. Exposed as
// a JsonnetLibrary for JaaS: author a workload as `function(params) …` and
// JaaS feeds the parameters as TLAs.

// Builds one flat array from parts that may be null (dropped) or nested arrays
// (flattened in one level), so a caller assembles a set with conditionals and
// optional groups. `if cond then value` with no else is null when cond is
// false, so an unmet condition simply drops out.
local join(parts) =
  local flatten(acc, part) =
    if std.isArray(part) then acc + part else acc + [part];
  std.foldl(flatten, std.filter(function(part) part != null, parts), []);

{
  // Base kinds — each a `function(name, image)` (cron also takes a schedule).
  http: import './lib/http.libsonnet',
  worker: import './lib/worker.libsonnet',
  cron: import './lib/cron.libsonnet',
  daemon: import './lib/daemon.libsonnet',
  stateful: import './lib/stateful.libsonnet',
  job: import './lib/job.libsonnet',

  // Composable axes.
  expose: import './lib/expose.libsonnet',
  security: import './lib/security.libsonnet',
  migrations: import './lib/migrations.libsonnet',

  // list renders every manifest of an app as a single `kind: List`, ready for
  // `kubectl apply --filename -` or as a JsonnetSnippet's published output.
  // The app's owned manifests (its store PVC, its config ConfigMap) ride along
  // — they are hidden fields, so std.objectValues skips them.
  list(app):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.objectValues(app)
           + (if std.objectHasAll(app, 'ownedManifests') then app.ownedManifests else []),
  },

  // join builds one flat array from parts that may be null or nested arrays —
  // assemble the parts of a value (a list of manifests, a set of args) with
  // conditionals and optional groups:
  //
  //   kurly.join([
  //     alwaysThis,
  //     if enabled then optionalThis,   // dropped when `enabled` is false
  //     [aGroupOfThings],               // flattened in
  //   ])
  join(parts):: join(parts),

  // listOf renders an explicit set of manifests as a `kind: List`. It joins the
  // parts first, so entries can be null (dropped — e.g. an absent owned
  // manifest) or nested arrays (flattened), letting a consumer build the set
  // with the same conditionals and optional groups as join.
  listOf(parts):: {
    apiVersion: 'v1',
    kind: 'List',
    items: std.filter(function(manifest) manifest != null, join(parts)),
  },

  // mirror points every image in already-rendered manifests at another
  // registry, for a cluster that pulls from a private one:
  //
  //   kurly.mirror('harbor.internal/dockerhub', kurly.list(app))
  //
  //   docker.io/valkey/valkey:9.0.3
  //     -> harbor.internal/dockerhub/valkey/valkey:9.0.3
  //
  // It rewrites the rendered output rather than the config on purpose, because
  // a workload's images are not all reachable from config. An initContainer's
  // spec is passed through verbatim, a sidecar can be grafted on with the raw
  // `+` escape hatch, and a custom resource's image is a field of someone
  // else's API — kurly.image() reaches none of them, so a config-level knob
  // would silently redirect the main container and leave the rest pulling from
  // the public internet. On a private-registry cluster that is not a partial
  // success: the pod does not start.
  //
  // Only the registry changes. Every image kurly renders is fully qualified
  // (docker.io/library/… , never library/…), so the registry is always the
  // first path segment and swapping it needs no reference parsing — the
  // repository, tag and digest are carried through untouched. `registry` may
  // itself carry a path (`harbor.internal/dockerhub`), which is what a
  // proxy-cache project wants.
  //
  // A transparent registry mirror configured on the nodes does this without
  // touching manifests at all, and is the better answer where it applies; this
  // is for a registry that renames the path, or an air-gapped copy.
  mirror(registry, manifests)::
    // Only `image` (containers, initContainers, sidecars, an ImageCatalog's
    // entries) and `imageName` (a CNPG Cluster) are rewritten. Rewriting every
    // field that merely looks like an image would reach into ConfigMap data and
    // arbitrary CR fields that happen to share a name.
    local rewriteRef(ref) =
      local slash = std.findSubstr('/', ref);
      // A reference with no slash carries no registry to replace, so it is left
      // alone rather than guessed at.
      if std.length(slash) == 0 then ref
      else registry + std.substr(ref, slash[0], std.length(ref) - slash[0]);
    local walk(node) =
      if std.isObject(node) then {
        [k]:
          // A ConfigMap's or Secret's payload is opaque application data that
          // happens to sit in a Kubernetes object; a key called `image` in there
          // is the application's, not the kubelet's. Descending into it would
          // rewrite a config value the moment it contained a slash — and
          // kurly.config({ image: 'foo/bar' }) is an ordinary thing to write.
          if k == 'data' || k == 'stringData' then node[k]
          else if (k == 'image' || k == 'imageName') && std.isString(node[k])
          then rewriteRef(node[k])
          else walk(node[k])
        for k in std.objectFields(node)
      }
      else if std.isArray(node) then [walk(item) for item in node]
      else node;
    walk(manifests),

  // A workload's stages are the ORDERED, GATED phases of installing ONE
  // application — apply a phase, wait for it to go healthy, then the next — not
  // environment tiers. Each stage is its OWN file under workloads/<name>/: a
  // `function(params)` returning a COMPOSABLE app (a base with defaults, no
  // exposure), which a consumer imports, adapts with `+` features, and renders
  // with kurly.list — one stage file maps to one stageset stage. Many workloads
  // need only ONE stage; do not manufacture ordering an application lacks.
  // (A PVC that binds WaitForFirstConsumer must ride with the pod that consumes
  // it, so it cannot be gated into a stage of its own.)
} + (import './lib/features.libsonnet')
