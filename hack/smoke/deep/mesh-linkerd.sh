#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for kurly.mesh.linkerd() against a real Linkerd control plane — the same
# five questions mesh-istio.sh asks, which is the point: the two recipes promise
# a consumer the same thing while emitting almost nothing in common, so the
# evidence for them has to be the same shape or the promise is not tested.
#
# Nothing here can be answered by rendering. Whether a pod gets a proxy is a
# decision Linkerd's injector makes about the object we emit, and whether
# plaintext is refused is a property of traffic — the same reason the
# catalogue's bsi is structurally silent about mTLS.
#
# Linkerd inverts Istio's mechanism at both ends, which is what steps 1 and 2
# are for. Its proxy-injector webhook is called for every pod in every namespace
# that has not opted out, and the injector then reads the ANNOTATION
# `linkerd.io/inject`; the label form Istio requires does nothing here. And its
# enforcement is not an object at all but the annotation
# `config.linkerd.io/default-inbound-policy`, which is why a meshed workload
# renders no extra manifest.
#
# What is proven, in order:
#
#   1. INJECTION HAPPENS from the recipe alone — the pod carries a
#      linkerd-proxy.
#   2. THE LABEL FORM DOES NOT — the same app carrying `linkerd.io/inject` as a
#      pod LABEL carries no proxy. The mirror image of mesh-istio.sh's step 2,
#      and together they are the evidence that the axis knows which mesh wants
#      which.
#   3. PLAINTEXT IS REFUSED — a client with no proxy cannot reach the workload.
#   4. THE MESH PATH WORKS — a client with a proxy can.
#   5. THE CONTROL: with the inbound policy back at Linkerd's own default and
#      nothing else changed, the proxy-less client CAN reach the workload.
#      Without this, step 3 proves only that a request failed, and a request can
#      fail for a hundred reasons that have nothing to do with mTLS.
#
# Linkerd's `stable` channel stopped at 2.14.10 when Buoyant moved it into their
# commercial distribution, so the open line is `edge` and that is what this
# pins.
cd "$(dirname "$0")/../../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=helm depName=linkerd-control-plane registryUrl=https://helm.linkerd.io/edge
LINKERD_VERSION="2026.8.1"

ns=kurly-mesh-linkerd
app_image="docker.io/traefik/whoami:v1.11.0"
client_image="docker.io/curlimages/curl:8.21.0"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::mesh state"
  kubectl --namespace="$ns" get pods -o wide 2>/dev/null || true
  echo "--- injector webhook selectors ---"
  kubectl get mutatingwebhookconfiguration linkerd-proxy-injector-webhook-config \
    -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}' 2>/dev/null || true
  echo "--- control plane ---"
  kubectl --namespace=linkerd get pods 2>/dev/null || true
  kubectl --namespace=linkerd logs deployment/linkerd-proxy-injector --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# Linkerd's identity system needs a trust anchor and an issuer signed by it, and
# helm — unlike the linkerd CLI — will not mint them. They are throwaway: this
# cluster is thrown away with them.
echo "== mint a throwaway trust anchor and issuer =="
step certificate create root.linkerd.cluster.local "${work}/ca.crt" "${work}/ca.key" \
  --profile root-ca --no-password --insecure >/dev/null || fail "could not create the trust anchor"
step certificate create identity.linkerd.cluster.local "${work}/issuer.crt" "${work}/issuer.key" \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca "${work}/ca.crt" --ca-key "${work}/ca.key" >/dev/null || fail "could not create the issuer"

echo "== install Linkerd edge-${LINKERD_VERSION} =="
helm repo add linkerd-edge https://helm.linkerd.io/edge >/dev/null
helm repo update >/dev/null
helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds \
  --version "$LINKERD_VERSION" --namespace linkerd --create-namespace --wait --timeout 5m \
  || fail "the Linkerd CRDs never installed"
helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane \
  --version "$LINKERD_VERSION" --namespace linkerd --wait --timeout 10m \
  --set-file identityTrustAnchorsPEM="${work}/ca.crt" \
  --set-file identity.issuer.tls.crtPEM="${work}/issuer.crt" \
  --set-file identity.issuer.tls.keyPEM="${work}/issuer.key" \
  || fail "the Linkerd control plane never became Ready"

kurly::vendor
kurly::namespace "$ns"

# Assert the namespace carries no injection annotation of its own, so a passing
# run can never be one where Linkerd injected everything regardless of what the
# recipe emitted.
[ "$(kubectl get namespace "$ns" -o 'jsonpath={.metadata.annotations.linkerd\.io/inject}')" = "" ] \
  || fail "${ns} is already annotated for injection: this scenario is only evidence without that"

# whoami is a static binary in a scratch image, so it meets the hardened default
# with a uid pinned and its port above 1024 — kurly's runAsNonRoot refuses the
# image on its default :80 as root, which is the recipe working rather than a
# problem to route around.
render_app() {
  local name="$1" compose="$2"
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet';
     k.list(k.http('${name}', '${app_image}')
       + k.port(8080) + k.env({ WHOAMI_PORT_NUMBER: '8080' })
       + k.runAs(65532) + k.replicas(1) + k.probes('/') + k.hostUsers() ${compose})"
}

# Whether the pods matching a selector carry a Linkerd proxy, as `yes` or `no`.
# Look for it BY NAME across both container lists: Linkerd injects as a native
# sidecar (a restartable init container) on a cluster new enough to have them, so
# a check counting spec.containers reports one container on a perfectly injected
# pod — the confident wrong answer mesh-istio.sh hit first.
has_proxy() {
  local names
  names="$(kubectl --namespace="$ns" get pods --selector="$1" \
    -o jsonpath='{.items[0].spec.containers[*].name} {.items[0].spec.initContainers[*].name}' 2>/dev/null)"
  if printf '%s' "$names" | grep -qw linkerd-proxy; then echo yes; else echo no; fi
}

# Whether the proxy-less client can reach $1 over plain HTTP. Echoes `yes` or
# `no`; never fails the scenario itself, because BOTH answers are the expected
# one at different points below.
plaintext_reaches() {
  if kubectl --namespace="$ns" exec plain-client -- \
    curl -sS --max-time 5 -o /dev/null "http://$1.${ns}.svc:8080/" >/dev/null 2>&1
  then echo yes; else echo no; fi
}

echo "== 1. the recipe injects a proxy =="
render_app meshed "+ k.mesh.linkerd()" | kubectl apply --namespace="$ns" --filename=- \
  || fail "the meshed app did not apply"
kubectl --namespace="$ns" rollout status deployment/meshed --timeout=300s \
  || fail "the meshed app never became Ready"
[ "$(has_proxy app.kubernetes.io/name=meshed)" = yes ] \
  || fail "the meshed app has no linkerd-proxy: the injection annotation did not take"
echo "ok: a proxy, from the annotation alone"

echo "== 2. the label form does NOT inject =="
# Injection is decided at ADMISSION, so this asks the pod SPEC and never waits
# for the pod to run. Waiting would make the answer depend on whether the app
# starts, which has nothing to do with the question and would report a node out
# of room as a mesh that injected.
render_app labelled "+ k.podLabels({ 'linkerd.io/inject': 'enabled' })" \
  | kubectl apply --namespace="$ns" --filename=- || fail "the labelled app did not apply"
for _ in $(seq 1 30); do
  [ -n "$(kubectl --namespace="$ns" get pods --selector=app.kubernetes.io/name=labelled -o name 2>/dev/null)" ] && break
  sleep 2
done
[ -n "$(kubectl --namespace="$ns" get pods --selector=app.kubernetes.io/name=labelled -o name 2>/dev/null)" ] \
  || fail "the labelled app produced no pod to inspect"
[ "$(has_proxy app.kubernetes.io/name=labelled)" = no ] \
  || fail "the labelled app got a proxy: this scenario's premise (Linkerd reads an annotation, not a label) is wrong"
echo "ok: no proxy — the label is invisible to this injector, the exact mirror of Istio"

echo "== a client on each side of the mesh =="
kubectl --namespace="$ns" run plain-client --image="$client_image" \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" run mesh-client --image="$client_image" \
  --annotations='linkerd.io/inject=enabled' \
  --restart=Never --command -- sleep 3600
for pod in plain-client mesh-client; do
  kubectl --namespace="$ns" wait --for=condition=Ready "pod/${pod}" --timeout=180s \
    || fail "${pod} never became Ready"
done
[ "$(has_proxy run=mesh-client)" = yes ] \
  || fail "mesh-client has no proxy, so step 4 would prove nothing"

echo "== 3. all-authenticated refuses the proxy-less client =="
[ "$(plaintext_reaches meshed)" = no ] \
  || fail "a client with no proxy reached the meshed workload: the inbound policy is not being enforced"
echo "ok: plaintext refused"

echo "== 4. the meshed client gets through =="
kubectl --namespace="$ns" exec mesh-client -- \
  curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' "http://meshed.${ns}.svc:8080/" \
  | grep -qx 200 || fail "a client inside the mesh could not reach the workload"
echo "ok: mTLS path works"

echo "== 5. control: at Linkerd's own default policy, the same request succeeds =="
# Re-render with the policy back at all-unauthenticated — same app, same
# injection, no enforcement — so the only thing that changed between this request
# and step 3's is the annotation the recipe sets. Re-rendering rather than
# patching keeps the manifest set the source of truth, the way a consumer would
# turn it off.
render_app meshed "+ k.mesh.linkerd(inboundPolicy='all-unauthenticated')" \
  | kubectl apply --namespace="$ns" --filename=- || fail "the re-render did not apply"
kubectl --namespace="$ns" rollout status deployment/meshed --timeout=300s \
  || fail "the meshed app never came back after the policy changed"
reached=no
for _ in $(seq 1 30); do
  reached="$(plaintext_reaches meshed)"
  [ "$reached" = yes ] && break
  sleep 2
done
[ "$reached" = yes ] \
  || fail "plaintext was still refused at all-unauthenticated: step 3's refusal was not this recipe's doing"
echo "ok: the refusal in step 3 came from the annotation the recipe sets"

echo "== clean up =="
kubectl delete namespace "$ns" --wait=false
helm uninstall linkerd-control-plane --namespace linkerd >/dev/null 2>&1 || true
helm uninstall linkerd-crds --namespace linkerd >/dev/null 2>&1 || true
kubectl delete namespace linkerd --wait=false 2>/dev/null || true

echo "ok: kurly.mesh.linkerd() injects, refuses unauthenticated traffic, and the refusal is its own"
