// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mesh: run a workload inside a service mesh, composed onto it with `+`. Another
// separate axis, the same shape as expose and network:
//
//   Istio:  kurly.mesh.istio()
//
// It does two things and deliberately not a third.
//
// IT ENABLES INJECTION, by putting the mesh's marker on the pod template — which
// is a label for Istio and an annotation for Linkerd, a difference the recipe
// knows so a consumer does not have to. That much was always reachable with
// kurly.podLabels, and a recipe that did only it would be a one-liner wearing a
// name that promised more.
//
// IT ENFORCES mTLS, by emitting a PeerAuthentication selecting the workload's own
// pods with `mode: STRICT` — the object that makes the sidecar refuse plaintext
// rather than merely accept TLS. This is the part worth a recipe, because it is
// the part a compliance regime asks about and the part NO ADMISSION POLICY CAN
// CHECK: a ValidatingAdmissionPolicy sees the object being written, so it cannot
// observe traffic and cannot require that some other object exists elsewhere. A
// workload passing every policy in the catalogue's `bsi` says nothing either way
// about whether its traffic is encrypted. Emitting the enforcing object is how a
// recipe can help where a policy engine structurally cannot.
//
// IT DOES NOT WRITE AN AuthorizationPolicy. Which principals may call which
// paths of this workload depends on what else the tenant runs, so it is not a
// fact a workload recipe knows — and Istio's authorization schema is large and
// moves. That is the restraint the network axis takes with the CNI schemas and
// migrations() takes with stageset Actions: model the small stable thing, and
// pass the rest through verbatim. `peerAuthentication` is that escape hatch here.
//
// The mTLS mode is a per-workload STRICT by default, not a namespace-wide one. A
// mesh-wide policy is an operator's decision about a cluster they installed, so
// it is offered separately as strictNamespace() below rather than smuggled into
// every workload that composes a mesh.
{
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
      mesh: {
        variant: 'istio',
        inject: inject,
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
        injectLabels: if inject then { 'sidecar.istio.io/inject': 'true' } else {},
        // Independent of `inject`: a cluster that injects by namespace label
        // still lets a pod say which image to inject, so the two knobs do not
        // gate each other.
        injectAnnotations:
          if proxyImage == null then {}
          else { 'sidecar.istio.io/proxyImage': proxyImage },
        mtls: mtls,
        peerAuthentication: peerAuthentication,
      },
    },
  },

  // A namespace-wide STRICT policy, for an operator setting the floor once
  // instead of per workload. Dropped into a manifest set with kurly.list, the
  // same way network.denyAll is:
  //
  //   kurly.list([ app, kurly.mesh.strictNamespace() ])
  //
  // It selects every pod in the namespace it is applied to, so it is not a
  // workload's to carry — a workload that emitted one would be legislating for
  // its neighbours.
  strictNamespace(name='default-strict-mtls', mtls='STRICT'):: {
    apiVersion: 'security.istio.io/v1',
    kind: 'PeerAuthentication',
    metadata: { name: name },
    spec: { mtls: { mode: mtls } },
  },
}
