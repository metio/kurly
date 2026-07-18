#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the status-responder workload and kurly's Gateway API path protection.
# It installs Envoy Gateway (the implementation that returns 500 for the empty-
# backendRefs "404" trick — so proving a clean 404 here is the whole point), then
# renders the pattern a consumer would: a shared not-found responder with a
# ReferenceGrant, and an app whose HTTPRoute guards /admin by routing it to that
# responder cross-namespace. It drives real traffic through the gateway.
#
# Four assertions, over one live gateway:
#   1. GET / through the gateway reaches the app (200).
#   2. GET /admin through the gateway is sunk to the responder (404, not 500) —
#      the path is off the public route.
#   3. The 404 body is the responder's, proving the guard routed there.
#   4. GET /admin on the app's own Service still returns 200 — the workload stays
#      reachable in-cluster; only the public route is blocked.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=docker depName=docker.io/envoyproxy/gateway-helm
ENVOY_GATEWAY_VERSION="v1.5.4"

gw_ns=gateway-infra
shared_ns=shared-http-services
app_ns=apps
host=app.example.com

fail() {
  echo "::error::$*"
  kurly::diagnose "$app_ns"
  kurly::diagnose "$shared_ns"
  echo "::group::gateway state"
  kubectl --namespace="$gw_ns" get gateway,httproute -o wide 2>/dev/null || true
  kubectl --namespace="$app_ns" get httproute -o yaml 2>/dev/null || true
  kubectl --namespace=envoy-gateway-system get pods,svc 2>/dev/null || true
  kubectl --namespace=envoy-gateway-system logs --selector=control-plane=envoy-gateway --tail=60 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install Envoy Gateway ${ENVOY_GATEWAY_VERSION} (brings the Gateway API CRDs) =="
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace envoy-gateway-system --create-namespace \
  --wait --timeout 5m
kubectl --namespace=envoy-gateway-system rollout status deployment/envoy-gateway --timeout=300s \
  || fail "Envoy Gateway did not start"

echo "== a GatewayClass and a shared Gateway with an HTTP listener =="
kubectl create namespace "$gw_ns" --dry-run=client -o yaml | kubectl apply -f -
# kind has no load balancer, so the default LoadBalancer data-plane Service stays
# <pending> forever and Envoy Gateway never assigns the Gateway an address —
# leaving it Programmed=False despite a healthy data plane. Provision the Service
# as ClusterIP (reachable in-cluster, which is all the probes need) via an
# EnvoyProxy config the GatewayClass points at.
kubectl apply -f - <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: clusterip-proxy
  namespace: ${gw_ns}
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: clusterip-proxy
    namespace: ${gw_ns}
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gw
  namespace: ${gw_ns}
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "${host}"
      allowedRoutes:
        namespaces:
          from: All
EOF
kubectl --namespace="$gw_ns" wait --for=condition=Programmed gateway/shared-gw --timeout=300s \
  || fail "the shared Gateway never became Programmed"

kurly::vendor
kurly::namespace "$shared_ns"
kurly::namespace "$app_ns"

echo "== deploy the shared not-found responder + a ReferenceGrant for the app namespace =="
# kind-in-CI cannot nest user namespaces, so relax that one knob; the rest of the
# restricted posture (read-only rootfs, dropped caps, seccomp, pinned uid) stands.
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list((import 'workloads/status-responder/responder.libsonnet')(name='not-found', statusCode=404, message='not found')
          + k.expose.referenceGrant(['${app_ns}']) + k.hostUsers())" \
  | kubectl apply --namespace="$shared_ns" --filename=-
kubectl --namespace="$shared_ns" rollout status deployment/not-found --timeout=180s \
  || fail "the not-found responder never became Available"

echo "== deploy the app (200 on every path) exposed through the gateway, guarding /admin =="
# The app is itself a fixed-200 responder, so it answers 200 on /admin too — which
# is exactly what proves the guard (public /admin -> 404) and internal reachability
# (direct /admin -> 200) are different paths, not the app returning 404 on its own.
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list((import 'workloads/status-responder/responder.libsonnet')(name='app', statusCode=200, message='app')
          + k.expose.gateway('${host}', 'shared-gw', gatewayNamespace='${gw_ns}')
          + k.expose.guard(['/admin'], 'not-found', serviceNamespace='${shared_ns}')
          + k.hostUsers())" \
  | kubectl apply --namespace="$app_ns" --filename=-
kubectl --namespace="$app_ns" rollout status deployment/app --timeout=180s \
  || fail "the app never became Available"
kubectl --namespace="$app_ns" wait --for=condition=Accepted httproute/app --timeout=120s \
  || fail "the app HTTPRoute was not Accepted by the gateway"

echo "== a client pod to drive traffic =="
kubectl --namespace="$app_ns" run client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$app_ns" wait --for=condition=Ready pod/client --timeout=120s \
  || fail "the client pod never became Ready"

# The Envoy Gateway data-plane Service provisioned for this Gateway. Reachable by
# ClusterIP in-cluster (its LoadBalancer stays Pending in kind, but routing works).
gw_svc=""
for _ in $(seq 1 30); do
  gw_svc="$(kubectl --namespace=envoy-gateway-system get svc \
    -l gateway.envoyproxy.io/owning-gateway-name=shared-gw \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "$gw_svc" ] && break
  sleep 5
done
[ -n "$gw_svc" ] || fail "Envoy Gateway never provisioned a data-plane Service for the Gateway"
gw="http://${gw_svc}.envoy-gateway-system.svc"

# curl through the gateway, carrying the route hostname. Returns "<status> <body>".
probe() {
  local url="$1" hosthdr="${2:-}"
  local args=(-s -o /tmp/body -w '%{http_code}' "$url")
  [ -n "$hosthdr" ] && args+=(-H "Host: ${hosthdr}")
  kubectl --namespace="$app_ns" exec client -- curl "${args[@]}" 2>/dev/null
  printf ' '
  kubectl --namespace="$app_ns" exec client -- cat /tmp/body 2>/dev/null
}

echo "== 1+2+3: drive traffic through the gateway =="
# Routing programs a moment after the Gateway is Programmed; poll until / answers.
ok=false
for _ in $(seq 1 24); do
  root="$(probe "${gw}/" "$host")"
  case "$root" in 200*) ok=true; break ;; esac
  echo "  gateway not routing yet (got '${root}'), retrying"
  sleep 5
done
[ "$ok" = true ] || fail "GET / through the gateway never returned 200 (got '${root:-}')"
echo "  GET /        -> ${root}"

admin="$(probe "${gw}/admin" "$host")"
echo "  GET /admin   -> ${admin}"
case "$admin" in
  404*"not found"*) : ;;
  500*) fail "GET /admin returned 500 — the guard did not sink the path (this is the empty-backendRefs failure mode the responder exists to avoid)" ;;
  200*) fail "GET /admin returned 200 — the guard did not take the path off the public route" ;;
  *) fail "GET /admin returned an unexpected response: '${admin}'" ;;
esac

echo "== 4: the app's own Service still serves /admin internally =="
internal="$(probe "http://app.${app_ns}.svc:5678/admin")"
echo "  GET /admin (direct) -> ${internal}"
case "$internal" in
  200*app*) : ;;
  *) fail "the app's own Service did not serve /admin (got '${internal}') — internal reachability is broken" ;;
esac

echo "status-responder works end to end: /admin is sunk to a clean 404 on the public gateway route while the app still serves it in-cluster — the portable Gateway API path protection the fixed-response filter would give, on an implementation that returns 500 for the native trick"
