#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for kurly.mesh.istio() against a real Istio control plane, proving the two
# claims the recipe makes and the one it is built to prevent.
#
# The claims cannot be checked by rendering. Whether a pod gets a sidecar is a
# decision Istio's admission webhook makes about the object we emit, and whether
# STRICT mTLS is enforced is a property of traffic — no policy engine can see
# either, which is the whole reason the recipe emits objects instead of the
# catalogue reporting a verdict. So the assertions here are a container count and
# two HTTP requests.
#
# The namespace is deliberately NOT labelled `istio-injection=enabled`. That is
# the case that separates a working marker from a decorative one: with the
# namespace labelled, Istio injects every pod regardless of what we put on it, so
# a scenario run there would pass with the recipe emitting nothing at all.
#
# What is proven, in order:
#
#   1. INJECTION HAPPENS from the recipe alone — the pod carries an istio-proxy
#      in an unlabelled namespace.
#   2. THE ANNOTATION FORM DOES NOT — the same app carrying
#      `sidecar.istio.io/inject: "true"` as a pod ANNOTATION carries none. This
#      is the bug the recipe was fixed for, kept as a live fact rather than a
#      reading of the webhook's selectors.
#   3. THE MESH PATH WORKS — a client with a sidecar reaches the workload. This
#      comes FIRST on purpose: it establishes that the endpoint answers at all,
#      without which the refusal below is just a request that failed.
#   4. PLAINTEXT IS REFUSED — a client with no sidecar cannot reach the same
#      endpoint that just answered.
#   5. THE CONTROL: with the PeerAuthentication removed and nothing else changed,
#      the sidecar-less client CAN reach the workload — so the refusal was that
#      object's doing and not something ambient.
cd "$(dirname "$0")/../../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=helm depName=istiod registryUrl=https://istio-release.storage.googleapis.com/charts
ISTIO_VERSION="1.30.3"

ns=kurly-mesh-istio
app_image="docker.io/traefik/whoami:v1.11.0"
client_image="docker.io/curlimages/curl:8.21.0"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::mesh state"
  kubectl --namespace="$ns" get pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get peerauthentication -o yaml 2>/dev/null | tail -40 || true
  echo "--- injection webhook selectors ---"
  kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
    -o jsonpath='{range .webhooks[*]}{.name}{"\n  ns: "}{.namespaceSelector}{"\n  obj: "}{.objectSelector}{"\n"}{end}' 2>/dev/null || true
  echo "--- istiod ---"
  kubectl --namespace=istio-system logs deployment/istiod --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# Renders a one-off http app composed the way the argument says. The app under
# test is a recipe rather than a catalogued workload, so it is written inline
# instead of imported from workloads/ — nothing in the fleet composes a mesh, and
# one that did would be testing the workload rather than the axis.
#
# whoami is a static binary in a scratch image, so it satisfies the hardened
# default with a uid pinned and its port moved above 1024 — kurly's runAsNonRoot
# refuses the image on its default :80 as root, which is the recipe working
# rather than a problem to route around.
render_app() {
  local name="$1" compose="$2"
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet';
     k.list(k.http('${name}', '${app_image}')
       + k.port(8080) + k.env({ WHOAMI_PORT_NUMBER: '8080' })
       + k.runAs(65532) + k.replicas(1) + k.probes('/') + k.hostUsers() ${compose})"
}

# Whether the pods matching a selector carry an Istio sidecar, as `yes` or `no`.
#
# Look for the container BY NAME, in both container lists. Modern Istio injects
# the proxy as a NATIVE SIDECAR — a restartable init container — rather than as a
# second entry in spec.containers, so a check counting spec.containers reports
# one container on a perfectly injected pod and concludes the marker did not
# take. That is precisely the shape of confident wrong answer this scenario
# exists to catch, and it caught it here first.
has_sidecar() {
  local names
  names="$(kubectl --namespace="$ns" get pods --selector="$1" \
    -o jsonpath='{.items[0].spec.containers[*].name} {.items[0].spec.initContainers[*].name}' 2>/dev/null)"
  if printf '%s' "$names" | grep -qw istio-proxy; then echo yes; else echo no; fi
}

# Whether the sidecar-less client can reach $1 over plain HTTP. Echoes `yes` or
# `no`; never fails the scenario itself, because BOTH answers are the expected
# one at different points below.
plaintext_reaches() {
  if kubectl --namespace="$ns" exec plain-client -- \
    curl -sS --max-time 5 -o /dev/null "http://$1.${ns}.svc/" >/dev/null 2>&1
  then echo yes; else echo no; fi
}

echo "== install Istio ${ISTIO_VERSION} =="
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo update >/dev/null
helm upgrade --install istio-base istio/base \
  --version "$ISTIO_VERSION" --namespace istio-system --create-namespace --wait --timeout 5m \
  || fail "the Istio base chart never installed"
helm upgrade --install istiod istio/istiod \
  --version "$ISTIO_VERSION" --namespace istio-system --wait --timeout 10m \
  || fail "istiod never became Ready"

kurly::vendor
kurly::namespace "$ns"

# Assert the namespace really is unlabelled, so a passing run can never be one
# where Istio injected everything regardless of what the recipe emitted.
for label in istio-injection istio.io/rev; do
  [ "$(kubectl get namespace "$ns" -o "jsonpath={.metadata.labels['${label//\//\\.}']}")" = "" ] \
    || fail "${ns} carries ${label}: this scenario is only evidence in an UNLABELLED namespace"
done

echo "== 1. the recipe injects a sidecar =="
render_app meshed "+ k.mesh.istio()" | kubectl apply --namespace="$ns" --filename=- \
  || fail "the meshed app did not apply"
kubectl --namespace="$ns" rollout status deployment/meshed --timeout=300s \
  || fail "the meshed app never became Ready"
[ "$(has_sidecar app.kubernetes.io/name=meshed)" = yes ] \
  || fail "the meshed app has no istio-proxy: the injection marker did not take"
echo "ok: a sidecar, in a namespace with no injection label"

echo "== 2. the annotation form does NOT inject =="
render_app annotated "+ k.podAnnotations({ 'sidecar.istio.io/inject': 'true' })" \
  | kubectl apply --namespace="$ns" --filename=- || fail "the annotated app did not apply"
kubectl --namespace="$ns" rollout status deployment/annotated --timeout=300s \
  || fail "the annotated app never became Ready"
[ "$(has_sidecar app.kubernetes.io/name=annotated)" = no ] \
  || fail "the annotated app got a sidecar: this scenario's premise (webhooks select on labels) is wrong, re-read the MutatingWebhookConfiguration"
echo "ok: no sidecar — the annotation is invisible to the injector, as the webhook's selectors say"

echo "== a client on each side of the mesh =="
kubectl --namespace="$ns" run plain-client --image="$client_image" \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" run mesh-client --image="$client_image" \
  --labels='sidecar.istio.io/inject=true,run=mesh-client' \
  --restart=Never --command -- sleep 3600
for pod in plain-client mesh-client; do
  kubectl --namespace="$ns" wait --for=condition=Ready "pod/${pod}" --timeout=180s \
    || fail "${pod} never became Ready"
done
[ "$(has_sidecar run=mesh-client)" = yes ] \
  || fail "mesh-client has no sidecar, so step 4 would prove nothing"

# The POSITIVE control comes first, and the order is load-bearing. "The request
# failed" is the weakest evidence in this file: a wrong port, a wrong name, a
# pod not yet serving all produce it, and each reads exactly like enforcement.
# Establishing that the endpoint answers a meshed client first is what turns the
# refusal below into a fact about the PeerAuthentication. The Linkerd scenario
# was written the other way round and passed its refusal against a port nothing
# was listening on.
echo "== 3. the meshed client gets through =="
kubectl --namespace="$ns" exec mesh-client -- \
  curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' "http://meshed.${ns}.svc/" \
  | grep -qx 200 || fail "a client inside the mesh could not reach the workload"
echo "ok: mTLS path works, so the endpoint demonstrably answers"

echo "== 4. STRICT refuses the sidecar-less client =="
[ "$(plaintext_reaches meshed)" = no ] \
  || fail "a client with no sidecar reached the meshed workload: STRICT mTLS is not being enforced"
echo "ok: plaintext refused"

echo "== 5. control: without the PeerAuthentication, the same request succeeds =="
# Re-render with mtls=null — same app, same injection, no enforcing object — so
# the only thing that changed between this request and step 3's is the object the
# recipe emits. Deleting the object by name would leave kurly.list's own output
# disagreeing with the cluster; re-rendering keeps the manifest set the source of
# truth, the way a consumer would turn it off.
render_app meshed "+ k.mesh.istio(mtls=null)" | kubectl apply --namespace="$ns" --filename=- \
  || fail "the re-render did not apply"
kubectl --namespace="$ns" delete peerauthentication meshed --ignore-not-found
# Enforcement is pushed to the sidecars asynchronously, so poll rather than
# assume the change has landed.
reached=no
for _ in $(seq 1 30); do
  reached="$(plaintext_reaches meshed)"
  [ "$reached" = yes ] && break
  sleep 2
done
[ "$reached" = yes ] \
  || fail "plaintext was still refused with no PeerAuthentication in place: step 4's refusal was not this recipe's doing"
echo "ok: the refusal in step 4 came from the object the recipe emits"

echo "== clean up =="
kubectl delete namespace "$ns" --wait=false
helm uninstall istiod --namespace istio-system >/dev/null 2>&1 || true
helm uninstall istio-base --namespace istio-system >/dev/null 2>&1 || true
kubectl delete namespace istio-system --wait=false 2>/dev/null || true

echo "ok: kurly.mesh.istio() injects, enforces STRICT mTLS, and the enforcement is its own"
