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

local httpRoute(app, host, parent) = {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: { name: app.config.name, labels: app.labels },
  spec: {
    parentRefs: [parent],
    hostnames: [host],
    rules: [{
      matches: [{ path: { type: 'PathPrefix', value: '/' } }],
      backendRefs: [{ name: app.config.name, port: 80 }],
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

{
  // ingress routes the host to the workload through the Ingress API.
  ingress(host, ingressClass=null):: exposure('ingress') {
    local app = self,

    ingress:
      k.networking.v1.ingress.new(app.config.name)
      + k.networking.v1.ingress.metadata.withLabels(app.labels)
      + (
        if ingressClass == null
        then {}
        else k.networking.v1.ingress.spec.withIngressClassName(ingressClass)
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
  ownGateway(host, gatewayClass):: exposure('ownGateway') {
    local app = self,

    gateway: {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'Gateway',
      metadata: { name: app.config.name, labels: app.labels },
      spec: {
        gatewayClassName: gatewayClass,
        listeners: [{
          name: 'http',
          protocol: 'HTTP',
          port: 80,
          hostname: host,
          allowedRoutes: { namespaces: { from: 'Same' } },
        }],
      },
    },

    httproute: httpRoute(app, host, { name: app.config.name }),
  },

  // ownListenerSet generates a ListenerSet that adds the workload's own
  // listener to a shared Gateway and routes the host through it. Gateways
  // reject ListenerSet attachment by default — the shared Gateway must opt in
  // via spec.allowedListeners.
  ownListenerSet(host, gateway, gatewayNamespace=null):: exposure('ownListenerSet') {
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
        listeners: [{
          name: 'http',
          protocol: 'HTTP',
          port: 80,
          hostname: host,
        }],
      },
    },

    httproute: httpRoute(app, host, listenerSetParent(app.config.name)),
  },
}
