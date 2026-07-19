// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// expose: routing features composed onto an HTTP workload with `+`. Exposure
// is a separate axis from the workload itself — pick the one recipe matching
// the cluster's routing API and ownership model:
//
//   Ingress API:   ingress(host)
//   Gateway API:   gateway(host, name)           — route to an existing Gateway
//                  listenerSet(host, name)       — route to an existing ListenerSet
//                  ownGateway(host, class)       — dedicated Gateway + route
//                  ownListenerSet(host, gateway) — own ListenerSet on a shared Gateway + route
//
// Every Gateway API recipe emits an HTTPRoute; the own* recipes additionally
// generate the parent it attaches to. All five join the `exposure` exclusion
// group, so composing two of them fails the render — a workload routes one way,
// and two recipes would emit conflicting or same-named objects. (An
// Ingress→Gateway migration runs the two as separate apps instead.)
//
// The Gateway API objects are written as plain manifests rather than through
// gateway-api-libsonnet, keeping the render-time dependency closure at
// k8s-libsonnet alone.
local k = import './k.libsonnet';

// Every exposure recipe needs a Service to route to — composing onto
// kurly.worker or kurly.cron is a mistake worth failing loudly on — and claims
// the shared `exposure` exclusion group so no two can coexist.
local exposure(name) = {
  assert std.objectHas(self, 'service') : 'kurly.expose recipes need a workload with a Service — compose them onto kurly.http',
  config+:: { exclusive+: { exposure+: [name] } },
};

// Guard rules (from kurly.expose.guard) come FIRST, the catch-all to the
// workload LAST. Gateway API resolves overlapping matches by specificity, not
// order, so a guarded `/admin` prefix wins over `/` for those requests
// regardless — the ordering is for the reader, not the router.
local httpRoute(app, host, parent) =
  // external-dns (from kurly.expose.dns) reads its record hints off the HTTPRoute,
  // so they ride in the route's annotations.
  local dnsAnnotations = std.get(app.config, 'dnsAnnotations', {});
  {
    apiVersion: 'gateway.networking.k8s.io/v1',
    kind: 'HTTPRoute',
    metadata: { name: app.config.name, labels: app.labels }
              + (if dnsAnnotations == {} then {} else { annotations: dnsAnnotations }),
    spec: {
      parentRefs: [parent],
      hostnames: [host],
      rules:
        std.get(app.config, 'guards', [])
        + [{
          matches: [{ path: { type: 'PathPrefix', value: '/' } }],
          backendRefs: [{ name: app.config.name, port: app.config.servicePort }],
        }],
    },
  };

local listenerSetParent(name, namespace=null, sectionName=null) = std.prune({
  group: 'gateway.networking.k8s.io',
  kind: 'ListenerSet',
  name: name,
  namespace: namespace,
  sectionName: sectionName,
});

// The listener a generated Gateway or ListenerSet publishes for `host`. Naming a
// certificate Secret makes it HTTPS on 443 and terminates there; naming none
// leaves it HTTP on 80. A workload that owns its listener and cannot terminate
// TLS is a workload that cannot serve HTTPS at all — the certificate is the
// cluster's (cert-manager writes the Secret, or a platform team mints it), so
// kurly cannot supply one, but it must let one be named.
local listener(host, tls) =
  if tls == null then {
    name: 'http',
    protocol: 'HTTP',
    port: 80,
    hostname: host,
  } else {
    name: 'https',
    protocol: 'HTTPS',
    port: 443,
    hostname: host,
    tls: {
      mode: 'Terminate',
      certificateRefs: [{ kind: 'Secret', name: tls }],
    },
  };

{
  // ingress routes the host to the workload through the Ingress API.
  //
  // `annotations` is not decoration: an Ingress controller takes its per-route
  // configuration from annotations and nothing else, and the keys belong to the
  // controller the cluster runs — cert-manager mints a certificate from
  // `cert-manager.io/cluster-issuer`, ingress-nginx reads
  // `nginx.ingress.kubernetes.io/*`, an AWS ALB reads `alb.ingress.kubernetes.io/*`.
  // kurly cannot know which controller is in front, so without them the route
  // renders and the cluster does something other than what was asked.
  //
  // `tls` names the Secret holding the certificate for `host`; with cert-manager
  // it is the Secret the issuer writes INTO, and need not exist beforehand.
  // Omitted, the route is plain HTTP — which is a choice, not a default worth
  // hiding.
  ingress(host, ingressClass=null, annotations={}, tls=null):: exposure('ingress') {
    local app = self,
    // The controller annotations plus any external-dns hints from kurly.expose.dns
    // — both live on the Ingress metadata (external-dns reads its records there).
    local ingressAnnotations = annotations + std.get(app.config, 'dnsAnnotations', {}),

    ingress:
      k.networking.v1.ingress.new(app.config.name)
      + k.networking.v1.ingress.metadata.withLabels(app.labels)
      + (if ingressAnnotations == {} then {} else k.networking.v1.ingress.metadata.withAnnotations(ingressAnnotations))
      + (
        if ingressClass == null
        then {}
        else k.networking.v1.ingress.spec.withIngressClassName(ingressClass)
      )
      + (
        if tls == null
        then {}
        else k.networking.v1.ingress.spec.withTls([{ hosts: [host], secretName: tls }])
      )
      + k.networking.v1.ingress.spec.withRules([{
        host: host,
        http: {
          paths: [{
            path: '/',
            pathType: 'Prefix',
            backend: {
              service: {
                name: app.config.name,
                port: { name: 'http' },
              },
            },
          }],
        },
      }]),
  },

  // gateway routes the host through an existing Gateway — the usual setup,
  // where a platform team owns a shared Gateway and workloads attach routes.
  gateway(host, gateway, gatewayNamespace=null, sectionName=null):: exposure('gateway') {
    local app = self,

    httproute: httpRoute(app, host, std.prune({
      name: gateway,
      namespace: gatewayNamespace,
      sectionName: sectionName,
    })),
  },

  // listenerSet routes the host through an existing ListenerSet — for
  // clusters where listener ownership is already delegated per tenant.
  listenerSet(host, listenerSet, listenerSetNamespace=null, sectionName=null):: exposure('listenerSet') {
    local app = self,

    httproute: httpRoute(app, host, listenerSetParent(listenerSet, listenerSetNamespace, sectionName)),
  },

  // ownGateway generates a dedicated Gateway for the workload and routes the
  // host through it — for clusters without a shared Gateway to attach to.
  //
  // A dedicated Gateway usually provisions a real load balancer, which is
  // configured through ANNOTATIONS whose keys belong to the implementation
  // (an AWS NLB, a GKE forwarding rule, an Istio deployment) — so they are the
  // consumer's to supply. `tls` names the Secret holding the certificate for
  // `host`; without one the listener is plain HTTP.
  ownGateway(host, gatewayClass, annotations={}, tls=null):: exposure('ownGateway') {
    local app = self,

    gateway: {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'Gateway',
      metadata: { name: app.config.name, labels: app.labels }
                + (if annotations == {} then {} else { annotations: annotations }),
      spec: {
        gatewayClassName: gatewayClass,
        listeners: [listener(host, tls) + { allowedRoutes: { namespaces: { from: 'Same' } } }],
      },
    },

    httproute: httpRoute(app, host, { name: app.config.name }),
  },

  // ownListenerSet generates a ListenerSet that adds the workload's own
  // listener to a shared Gateway and routes the host through it. Gateways
  // reject ListenerSet attachment by default — the shared Gateway must opt in
  // via spec.allowedListeners.
  // Owning the listener is the whole point of a ListenerSet, so the certificate
  // for `host` is the consumer's to name; without one it is plain HTTP.
  ownListenerSet(host, gateway, gatewayNamespace=null, tls=null):: exposure('ownListenerSet') {
    local app = self,

    listenerset: {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'ListenerSet',
      metadata: { name: app.config.name, labels: app.labels },
      spec: {
        parentRef: std.prune({
          group: 'gateway.networking.k8s.io',
          kind: 'Gateway',
          name: gateway,
          namespace: gatewayNamespace,
        }),
        listeners: [listener(host, tls)],
      },
    },

    httproute: httpRoute(app, host, listenerSetParent(app.config.name)),
  },

  // guard sinks specific path prefixes on the workload's HTTPRoute to a
  // status-responder Service instead of the workload — the portable way to take
  // a path OFF the public internet (answer 403/404) while the workload stays
  // reachable in-cluster. Compose it AFTER a Gateway API exposure; it adds a rule
  // to that exposure's HTTPRoute rather than emitting its own, so it is a
  // modifier, not an exposure, and joins no exclusion group. Gateway API resolves
  // overlapping matches by specificity, so the guarded prefix wins over the
  // catch-all for those requests.
  //
  // `service` is usually the shared kurly status-responder in another namespace;
  // a cross-namespace backendRef needs a ReferenceGrant on that side (see
  // referenceGrant). All the given paths share one rule (one responder); compose
  // guard twice to sink different paths to different responders (an /admin 403
  // and a /metrics 404).
  //
  //   kurly.http('etherpad', image)
  //   + kurly.expose.listenerSet('pad.example.com', 'shared')
  //   + kurly.expose.guard(['/admin', '/stats'], 'not-found', serviceNamespace='shared-http-services')
  guard(paths, service, serviceNamespace=null, port=5678):: {
    assert std.objectHas(self, 'httproute') :
           'kurly.expose.guard adds rules to a Gateway API HTTPRoute — compose it after gateway/listenerSet/ownGateway/ownListenerSet',
    config+:: {
      guards+: [{
        matches: [{ path: { type: 'PathPrefix', value: p } } for p in paths],
        backendRefs: [std.prune({ name: service, namespace: serviceNamespace, port: port })],
      }],
    },
  },

  // dns adds external-dns annotations to the exposure's DNS-bearing resource (the
  // HTTPRoute for a Gateway API recipe, the Ingress for the Ingress one), so
  // external-dns creates the record. A modifier composed AFTER an exposure, not an
  // exposure itself, and joins no exclusion group. external-dns already discovers
  // the exposed hostname on its own — reach for this to OVERRIDE: a different or
  // additional `hostname`, a `ttl`, or a `target` (the address/CNAME the record
  // points at, rather than the gateway's own). `annotations` passes through any
  // provider-specific keys (external-dns.alpha.kubernetes.io/cloudflare-proxied,
  // aws-weight, …).
  //
  //   kurly.http('web', image)
  //   + kurly.expose.ownGateway('web.example.com', 'istio')
  //   + kurly.expose.dns(target='ingress.example.net.', ttl=300)
  dns(hostname=null, ttl=null, target=null, annotations={}):: {
    assert std.objectHas(self, 'httproute') || std.objectHas(self, 'ingress') :
           'kurly.expose.dns annotates a route or ingress — compose it after an exposure recipe',
    config+:: {
      dnsAnnotations+:
        std.prune({
          'external-dns.alpha.kubernetes.io/hostname': hostname,
          'external-dns.alpha.kubernetes.io/ttl': (if ttl == null then null else std.toString(ttl)),
          'external-dns.alpha.kubernetes.io/target': target,
        })
        + annotations,
    },
  },

  // referenceGrant lets HTTPRoutes in OTHER namespaces route to this workload's
  // Service — the cross-namespace consent Gateway API requires, granted on the
  // Service (the `to`) side and naming the namespaces allowed to reach it. This
  // is what makes a shared status-responder usable from tenant namespaces: deploy
  // the responder once, grant the tenants, and their guard rules can target its
  // Service. Like guard it is a modifier (needs a Service to grant, joins no
  // exclusion group), composed onto the responder:
  //
  //   responder(name='not-found', statusCode=404, message='not found')
  //   + kurly.expose.referenceGrant(['team-a', 'team-b'])
  referenceGrant(fromNamespaces):: {
    assert std.objectHas(self, 'service') :
           'kurly.expose.referenceGrant grants access to a workload Service — compose it onto kurly.http (or another kind with a Service)',
    local app = self,

    // v1: ReferenceGrant is in the Gateway API standard channel as of 1.5, the
    // release line kurly targets. (It served only v1beta1 before 1.5.)
    referencegrant: {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'ReferenceGrant',
      metadata: { name: app.config.name, labels: app.labels },
      spec: {
        from: [
          { group: 'gateway.networking.k8s.io', kind: 'HTTPRoute', namespace: namespace }
          for namespace in fromNamespaces
        ],
        to: [{ group: '', kind: 'Service', name: app.config.name }],
      },
    },
  },
}
