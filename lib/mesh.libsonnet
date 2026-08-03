// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mesh: run a workload inside a service mesh, composed onto it with `+`. Another
// separate axis, the same shape as expose and network:
//
//   Istio:    kurly.mesh.istio()
//   Linkerd:  kurly.mesh.linkerd()
//
// Each recipe does two things and deliberately not a third.
//
// IT ENABLES INJECTION, by putting the mesh's marker on the pod template. Which
// marker is the mesh's business rather than the consumer's, and the two do not
// agree: Istio's webhook selects on a LABEL, Linkerd's injector reads an
// ANNOTATION. Getting that backwards is silent — the pod is admitted, carries no
// proxy, and nothing says so.
//
// IT REFUSES PLAINTEXT, which is the half worth a recipe. A compliance regime
// asks about encryption in transit, and NO ADMISSION POLICY CAN ANSWER: a
// ValidatingAdmissionPolicy sees the object being written, so it cannot observe
// traffic and cannot require that some other object exists elsewhere. A workload
// passing every policy in the catalogue's `bsi` says nothing either way about
// whether its traffic is encrypted. Rendering the thing that enforces it is
// where a recipe can help and a policy engine structurally cannot.
//
// The two meshes do that differently enough that a shared vocabulary would be a
// lie rather than an abstraction. Istio emits an OBJECT — a PeerAuthentication
// with mode STRICT. Linkerd sets an ANNOTATION — a default inbound policy of
// all-authenticated, meaning the proxy accepts only mesh-authenticated clients.
// So each recipe takes its own native knob with its own vocabulary, and the
// neutral promise lives at the recipe: `kurly.mesh.<mesh>()` with no arguments
// means "meshed, plaintext refused" in both.
//
// NEITHER WRITES AN AUTHORIZATION RULE (Istio's AuthorizationPolicy, Linkerd's
// Server/AuthorizationPolicy). Which principals may call which paths of this
// workload depends on what else the tenant runs, so it is not a fact a workload
// recipe knows — and both schemas are large and move. That is the restraint the
// network axis takes with the CNI schemas and migrations() takes with stageset
// Actions: model the small stable thing, and pass the rest through verbatim.
{
  // A neutral config.mesh slot, so every variant writes the same shape and the
  // base's computed fields dispatch on `variant` rather than on which optional
  // fields happen to be present.
  local slot(variant, inject, injectLabels, injectAnnotations, mtls, peerAuthentication) = {
    variant: variant,
    inject: inject,
    injectLabels: injectLabels,
    injectAnnotations: injectAnnotations,
    mtls: mtls,
    peerAuthentication: peerAuthentication,
  },

  // A recipe claims the shared `mesh` exclusion group, so two meshes cannot
  // compose onto one workload, and asserts it landed on a real workload rather
  // than on a custom resource that would read none of it.
  //
  // The assert reads a knob only base.core sets, NOT the presence of `config`
  // itself: this very mixin contributes `config`, so asking whether the merged
  // object has one is a question that answers itself and admits everything.
  local mesh(name) = {
    assert std.objectHasAll(self.config, 'name') :
           'kurly.mesh recipes configure a workload — compose them onto a kurly kind (http, worker, …)',
    config+:: { exclusive+: { mesh+: [name] } },
  },

  // istio enables sidecar injection and enforces mTLS for this workload's pods.
  //
  //   mtls   'STRICT'     the sidecar refuses plaintext (the default, and the
  //                       only mode that constitutes encryption in transit)
  //          'PERMISSIVE' accepts both, for migrating a namespace
  //          'DISABLE'    no mTLS
  //          null         emit no PeerAuthentication at all, leaving the
  //                       namespace or mesh default in force
  //   inject  false to skip the injection marker, for a cluster that labels the
  //           namespace instead
  //   proxyImage  the image the injected containers pull, overriding the mesh's
  //           default. Istio publishes from registry.istio.io/release, which an
  //           allow-list cluster does not permit and an air-gapped one cannot
  //           reach — and no amount of care in this manifest changes an image
  //           the injector chose. One annotation covers BOTH injected
  //           containers: istiod's template reads it for the proxy and for
  //           istio-init alike.
  //   peerAuthentication  merged verbatim into the emitted object's spec, for
  //           the per-port overrides this vocabulary does not model
  istio(mtls='STRICT', inject=true, proxyImage=null, peerAuthentication={}):: mesh('istio') {
    config+:: {
      mesh: slot(
        'istio',
        inject,
        // A LABEL, not an annotation, and on the POD template rather than the
        // controller. Both halves of that are load-bearing.
        //
        // Istio's MutatingWebhookConfiguration selects on labels only — an
        // objectSelector cannot read annotations. In a namespace carrying
        // neither `istio-injection` nor `istio.io/rev`, the one webhook that can
        // fire requires `sidecar.istio.io/inject: "true"` IN THE POD'S LABELS,
        // so the annotation form injects nothing at all there and does so
        // silently. In a namespace that IS labelled, the webhook fires for every
        // pod regardless and the "true" value falls outside its NotIn ["false"]
        // exclusion, so the label is right in both worlds.
        //
        // And the marker belongs to the pod: the injector mutates pods, so one
        // on the Deployment reaches nothing.
        if inject then { 'sidecar.istio.io/inject': 'true' } else {},
        // Independent of `inject`: a cluster that injects by namespace label
        // still lets a pod say which image to inject, so the two knobs do not
        // gate each other.
        if proxyImage == null then {} else { 'sidecar.istio.io/proxyImage': proxyImage },
        mtls,
        peerAuthentication,
      ),
    },
  },

  // linkerd enables proxy injection and refuses unauthenticated inbound traffic.
  //
  // Everything here is an ANNOTATION, including the enforcement — Linkerd has no
  // object equivalent to a PeerAuthentication. Its proxy-injector webhook is
  // called for every pod in every namespace that has not opted out, and the
  // injector then reads `linkerd.io/inject` to decide, so unlike Istio there is
  // no namespace to label first.
  //
  //   inboundPolicy  what the proxy accepts on inbound connections:
  //          'all-authenticated'      only mesh-authenticated (mTLS) clients —
  //                                   the default here, and the one that
  //                                   constitutes encryption in transit
  //          'cluster-authenticated'  authenticated clients from the cluster
  //                                   networks only
  //          'all-unauthenticated'    anything, which is Linkerd's own default
  //          'deny' / 'audit'         refuse everything no Server names / allow
  //                                   it but log what would have been refused
  //          null                     set nothing, leaving the namespace or
  //                                   control-plane default in force
  //   inject  false to skip the injection annotation, for a namespace annotated
  //          with linkerd.io/inject already
  //   proxyImage  the image the injected proxy pulls. Linkerd publishes from
  //          cr.l5d.io, which an allow-list cluster does not permit and an
  //          air-gapped one cannot reach.
  linkerd(inboundPolicy='all-authenticated', inject=true, proxyImage=null):: mesh('linkerd') {
    config+:: {
      mesh: slot(
        'linkerd',
        inject,
        {},
        (if inject then { 'linkerd.io/inject': 'enabled' } else {})
        + (if inboundPolicy == null then {} else { 'config.linkerd.io/default-inbound-policy': inboundPolicy })
        + (if proxyImage == null then {} else { 'config.linkerd.io/proxy-image': proxyImage }),
        // Linkerd enforces through the annotations above, so the slot's
        // object-shaped fields stay empty and the base emits no manifest for it.
        null,
        {},
      ),
    },
  },

  // The namespace-wide floor, for an operator setting it once instead of per
  // workload. Dropped into a manifest set with kurly.list, the same way
  // network.denyAll is:
  //
  //   kurly.list([ app, kurly.mesh.strictNamespace.istio() ])
  //
  // It selects every pod in the namespace it is applied to, so it is not a
  // workload's to carry — a workload that emitted one would be legislating for
  // its neighbours.
  //
  // There is no linkerd member, and the absence is the answer rather than a gap:
  // Linkerd's namespace floor is an annotation on the NAMESPACE object, or
  // `proxy.defaultInboundPolicy` on the control plane. kurly renders neither —
  // its objects are namespace-less by design, placed by the consumer — so a
  // generator here would have to author someone else's namespace to say it.
  strictNamespace:: {
    istio(name='default-strict-mtls', mtls='STRICT'):: {
      apiVersion: 'security.istio.io/v1',
      kind: 'PeerAuthentication',
      metadata: { name: name },
      spec: { mtls: { mode: mtls } },
    },
  },
}
