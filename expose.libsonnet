// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// expose: routing recipes composed onto an HTTP workload with `+`. Exposure
// is a separate axis from the workload itself — pick the recipe matching the
// cluster's routing API and ownership model:
//
//   Ingress API:   ingress(host)
//   Gateway API:   gateway(host, name)           — route to an existing Gateway
//                  listenerSet(host, name)       — route to an existing XListenerSet
//                  ownGateway(host, class)       — dedicated Gateway + route
//                  ownListenerSet(host, gateway) — own XListenerSet on a shared Gateway + route
//
// Every Gateway API recipe emits an HTTPRoute; the own* recipes additionally
// generate the parent it attaches to. Each recipe captures its host argument
// lexically, so composing several exposures (e.g. an Ingress→Gateway
// migration running both) keeps each host independent.
//
// The Gateway API objects are written as plain manifests rather than through
// gateway-api-libsonnet, keeping the render-time dependency closure at
// k8s-libsonnet alone.
local k = import './k.libsonnet';

// Exposure needs a Service to route to — composing onto kurly.worker or
// kurly.cron is a mistake worth failing loudly on.
local requiresService = {
  assert std.objectHas(self, 'service') : 'kurly.expose recipes need a workload with a Service — compose them onto kurly.http',
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
  group: 'gateway.networking.x-k8s.io',
  kind: 'XListenerSet',
  name: name,
  namespace: namespace,
  sectionName: sectionName,
});

{
  // ingress routes the host to the workload through the Ingress API.
  ingress(host, ingressClass=null):: requiresService {
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
  gateway(host, gateway, gatewayNamespace=null, sectionName=null):: requiresService {
    local app = self,

    httproute: httpRoute(app, host, std.prune({
      name: gateway,
      namespace: gatewayNamespace,
      sectionName: sectionName,
    })),
  },

  // listenerSet routes the host through an existing XListenerSet — for
  // clusters where listener ownership is already delegated per tenant.
  listenerSet(host, listenerSet, listenerSetNamespace=null, sectionName=null):: requiresService {
    local app = self,

    httproute: httpRoute(app, host, listenerSetParent(listenerSet, listenerSetNamespace, sectionName)),
  },

  // ownGateway generates a dedicated Gateway for the workload and routes the
  // host through it — for clusters without a shared Gateway to attach to.
  ownGateway(host, gatewayClass):: requiresService {
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

  // ownListenerSet generates an XListenerSet that adds the workload's own
  // listener to a shared Gateway (which must allow ListenerSet attachment)
  // and routes the host through it.
  ownListenerSet(host, gateway, gatewayNamespace=null):: requiresService {
    local app = self,

    listenerset: {
      apiVersion: 'gateway.networking.x-k8s.io/v1alpha1',
      kind: 'XListenerSet',
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
