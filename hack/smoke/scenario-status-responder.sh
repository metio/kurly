#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the status-responder workload and kurly's Gateway API path protection.
# It installs the Gateway API standard-channel CRDs (the stable channel, latest
# release — the only surface kurly targets) and Envoy Gateway as the runtime (the
# implementation that returns 500 for the empty-backendRefs "404" trick, so
# proving a clean 404 here is the whole point), then renders the pattern a
# consumer would: a shared not-found responder with a ReferenceGrant, and an app
# whose HTTPRoute guards /admin by routing it to that responder cross-namespace.
# It drives real traffic through the gateway.
#
# Five assertions, over one live gateway:
#   1. GET / through the gateway reaches the app (200).
#   2. GET /admin through the gateway is sunk to the responder (404, not 500) —
#      the path is off the public route.
#   3. The 404 body is the responder's, proving the guard routed there.
#   4. GET /admin on the app's own Service still returns 200 — the workload stays
#      reachable in-cluster; only the public route is blocked.
#   5. expose.ownListenerSet grafts a second app's own listener onto the shared
#      Gateway (ListenerSet, standard channel since Gateway API 1.5) and traffic
#      to its hostname routes through it.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# The Gateway API release whose STANDARD channel CRDs the cluster gets — the
# stable channel, latest release, the only surface kurly targets.
# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
GATEWAY_API_VERSION="v1.6.0"

# Envoy Gateway is the runtime; 1.8 is the first line that supports Gateway API
# 1.5. It supplies only its own CRDs here — the Gateway API CRDs come from the
# release above, not from EG's bundle.
# renovate: datasource=docker depName=docker.io/envoyproxy/gateway-helm
ENVOY_GATEWAY_VERSION="v1.8.2"

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
  kubectl --namespace="$app_ns" get httproute,listenerset -o yaml 2>/dev/null || true
  kubectl --namespace=envoy-gateway-system get pods,svc 2>/dev/null || true
  kubectl --namespace=envoy-gateway-system logs --selector=control-plane=envoy-gateway --tail=60 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# Polls an HTTPRoute's Accepted condition. It lives under status.parents[] (one
# set of conditions per attached parent), not the top-level status.conditions that
# `kubectl wait --for=condition=Accepted` reads — so kubectl wait can never see it.
# A route parented to a ListenerSet reports Accepted here only once that parent
# admits it, so this doubles as the ListenerSet-attachment check.
route_accepted() {
  local ns=$1 name=$2 acc
  for _ in $(seq 1 24); do
    acc="$(kubectl --namespace="$ns" get httproute "$name" \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)"
    [ "$acc" = "True" ] && return 0
    sleep 5
  done
  return 1
}

echo "== install the Gateway API ${GATEWAY_API_VERSION} STANDARD-channel CRDs =="
# kurly targets the Gateway API stable channel, latest release — so the cluster
# gets exactly the standard-channel CRDs, never the experimental ones. A manifest
# that strayed to an experimental-only kind (or an apiVersion only served there)
# would fail to apply here, which is the point. Applied straight from the Gateway
# API release, not from a runtime's bundle, so the version is pinned and stable.
# Server-side apply: these CRD schemas exceed the last-applied-configuration
# annotation a client-side apply would write (and they are far too large for a
# Helm chart, whose release Secret caps at 1 MiB).
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "== install the Envoy Gateway CRDs =="
# EG's own CRDs only (the Gateway API set is installed above). EG 1.8 templates
# its CRDs into the release manifest, and gzip'd they too overflow Helm's 1 MiB
# release Secret — so render them and apply with kubectl, no release object and no
# size cap, the same way the Gateway API CRDs went on. Pull first and template the
# LOCAL copy: `helm template` on an OCI ref writes "Pulled:"/"Digest:" to stdout,
# which would land in the pipe as a bogus YAML document (no kind) that kubectl
# rejects.
eg_crds="$(mktemp -d)"
helm pull oci://docker.io/envoyproxy/gateway-crds-helm --version "$ENVOY_GATEWAY_VERSION" \
  --destination "$eg_crds" --untar
helm template eg-crds "$eg_crds/gateway-crds-helm" \
  --set crds.gatewayAPI.enabled=false \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -

echo "== install Envoy Gateway ${ENVOY_GATEWAY_VERSION} (controller only) =="
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace envoy-gateway-system --create-namespace \
  --set crds.enabled=false \
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
  # Opt in to ListenerSet attachment (Gateways reject it by default) so the
  # ownListenerSet check below can graft its own listener onto this Gateway.
  allowedListeners:
    namespaces:
      from: All
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
route_accepted "$app_ns" app \
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

# ---------------------------------------------------------------------------
# Assertion 5 — expose.ownListenerSet grafts a workload's own listener onto the
# shared Gateway and routes through it. ListenerSet is standard-channel as of
# Gateway API 1.5, so this exercises kurly's newest exposure recipe on a real
# runtime: the Gateway opted in via allowedListeners above, and traffic to the
# ListenerSet's own hostname must reach the workload through the same Gateway.
# ---------------------------------------------------------------------------

ls_host=owned.example.com
echo "== 5: deploy an app exposed through its OWN ListenerSet on the shared Gateway =="
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list((import 'workloads/status-responder/responder.libsonnet')(name='owned-app', statusCode=200, message='owned')
          + k.expose.ownListenerSet('${ls_host}', 'shared-gw', gatewayNamespace='${gw_ns}')
          + k.hostUsers())" \
  | kubectl apply --namespace="$app_ns" --filename=-
kubectl --namespace="$app_ns" rollout status deployment/owned-app --timeout=180s \
  || fail "the ownListenerSet app never became Available"
# The route parents to the generated ListenerSet, so Accepted here means the
# ListenerSet admitted it; the traffic check below proves the ListenerSet's
# listener is actually programmed on the shared Gateway and routes.
route_accepted "$app_ns" owned-app \
  || fail "the ownListenerSet HTTPRoute was not Accepted — the ListenerSet did not admit it (check the Gateway's allowedListeners opt-in)"

owned=false
for _ in $(seq 1 24); do
  resp="$(probe "${gw}/" "$ls_host")"
  case "$resp" in 200*owned*) owned=true; break ;; esac
  echo "  ListenerSet route not serving yet (got '${resp}'), retrying"
  sleep 5
done
[ "$owned" = true ] || fail "GET / on the ListenerSet's own hostname never reached the app (got '${resp:-}')"
echo "  GET / (owned listener) -> ${resp}"

echo "status-responder works end to end: /admin is sunk to a clean 404 on the public gateway route while the app still serves it in-cluster — the portable Gateway API path protection the fixed-response filter would give, on an implementation that returns 500 for the native trick — and a second app routes through its own ListenerSet grafted onto the shared Gateway"
