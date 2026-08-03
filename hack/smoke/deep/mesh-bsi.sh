#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# What does putting a workload in a mesh COST it at admission?
#
#   mesh-bsi.sh [istio|linkerd]
#
# kurly's recipes keep a hardened posture that the bollwerk policies are built to
# check, and the catalogue publishes the result per stage. But `bsi` is measured
# on what kurly RENDERS, and a meshed pod is not what kurly renders: the injector
# adds containers of its own between the manifest and the pod. Those containers
# are subject to the same policies — `pods` is in bollwerk's scope — and nothing
# has measured them.
#
# This matters beyond curiosity. A platform offering mTLS as a compliance
# feature is offering two things that can be in tension: an encrypted mesh and an
# enforced admission baseline. If the sidecar breaks the baseline, an operator
# has to know that before selling both.
#
# METHOD, and why the control is the point. The same app is deployed twice into
# the same namespace, once with kurly.mesh.istio() and once without. Each
# resulting pod is taken as the API server actually stored it, stripped of what
# exists only because it is running, and re-submitted as a dry-run CREATE so the
# policies warn to US rather than to whoever created it — the method cr-bsi.sh
# uses for operator-made pods. The answer is the DIFFERENCE between the two
# lists. Reporting the meshed pod's violations alone would credit the sidecar
# with every policy the bare workload already broke.
#
# Then it measures the mesh a SECOND time with that mesh's CNI plugin installed.
# Both meshes have the same problem and the same escape: by default each programs
# the pod's iptables from an init container running as root with NET_ADMIN and
# NET_RAW — everything the baseline exists to forbid — and each offers a CNI
# plugin that moves the work to a node agent so the injected pod no longer needs
# it. Whether that actually clears the violations is a question about a running
# cluster, and the point of asking it here is that an operator who has to offer
# both an encrypted mesh and an enforced baseline needs the configuration that
# gives them both, not the news that they conflict.
#
# Stripping volumes (as cr-bsi.sh does, so the dry-run does not fail on objects
# that are not there) means any policy reading volume names is under-measured for
# both pods equally. The security-context policies this is about read the
# containers, which are kept intact.
set -uo pipefail

cd "$(dirname "$0")/../../.." || exit 1
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=helm depName=istiod registryUrl=https://istio-release.storage.googleapis.com/charts
ISTIO_VERSION="1.30.3"
# renovate: datasource=helm depName=linkerd-control-plane registryUrl=https://helm.linkerd.io/edge
LINKERD_VERSION="2026.8.1"

MESH="${1:-istio}"
case "$MESH" in
  istio | linkerd) ;;
  *) echo "::error::unknown mesh '${MESH}' — use istio or linkerd"; exit 1 ;;
esac

ns=kurly-mesh-bsi
app_image="docker.io/traefik/whoami:v1.11.0"

# Everything that differs between the two meshes, in one place: the container
# each injects to program iptables (the one the CNI plugin removes), the proxy
# it injects, the label its CNI node agent carries, and the recipe to compose.
case "$MESH" in
  istio)
    proxy_container=istio-proxy
    cni_selector=k8s-app=istio-cni-node
    cni_namespace=istio-system
    compose="+ k.mesh.istio()"
    ;;
  linkerd)
    proxy_container=linkerd-proxy
    cni_selector=k8s-app=linkerd-cni
    cni_namespace=linkerd-cni
    compose="+ k.mesh.linkerd()"
    ;;
esac

# The policies are cluster-scoped, so this must never run against a cluster
# anyone relies on — even as Warn, they would annotate everything admitted there.
context="$(kubectl config current-context 2>/dev/null || true)"
case "$context" in
  kind-*) ;;
  *)
    echo "::error::refusing to run against non-kind context '${context}'; this installs cluster-wide policies"
    exit 1
    ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "::error::$*"
  kubectl --namespace="$ns" get pods -o wide 2>/dev/null || true
  exit 1
}

install_istio() {
  echo "== install Istio ${ISTIO_VERSION} =="
  helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
  helm repo update >/dev/null
  helm upgrade --install istio-base istio/base \
    --version "$ISTIO_VERSION" --namespace istio-system --create-namespace --wait --timeout 5m \
    || fail "the Istio base chart never installed"
  helm upgrade --install istiod istio/istiod \
    --version "$ISTIO_VERSION" --namespace istio-system --wait --timeout 10m \
    || fail "istiod never became Ready"
}

# Linkerd's identity system needs a trust anchor and an issuer signed by it, and
# helm — unlike the linkerd CLI — will not mint them. Throwaway, like the cluster.
install_linkerd() {
  echo "== install Linkerd edge-${LINKERD_VERSION} =="
  step certificate create root.linkerd.cluster.local "${work}/ca.crt" "${work}/ca.key" \
    --profile root-ca --no-password --insecure >/dev/null || fail "could not create the trust anchor"
  step certificate create identity.linkerd.cluster.local "${work}/issuer.crt" "${work}/issuer.key" \
    --profile intermediate-ca --not-after 8760h --no-password --insecure \
    --ca "${work}/ca.crt" --ca-key "${work}/ca.key" >/dev/null || fail "could not create the issuer"
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
}

"install_${MESH}"

# Every binding as Warn, for the reason gen-bsi installs them that way: Deny
# stops at the first violation and Audit only reaches the audit log, while Warn
# returns EVERY violating policy as a warning header and admits the object.
echo "== install every bollwerk policy as Warn =="
jsonnet -e 'local b = import "bollwerk/bollwerk.libsonnet";
  {
    apiVersion: "v1",
    kind: "List",
    items: [
      if i.kind == "ValidatingAdmissionPolicyBinding" then i + { spec+: { validationActions: ["Warn"] } } else i
      for i in b.list.items
    ],
  }' > "${work}/policies.json"
kubectl apply --filename="${work}/policies.json" >/dev/null || fail "the bollwerk policies did not install"

kurly::vendor
kurly::namespace "$ns"

# Same app, same everything, composed twice. whoami is a static binary in a
# scratch image, so it meets the hardened default with a uid pinned and its port
# above 1024 — the bare pod should break nothing, which is what makes the
# difference readable.
render_app() {
  local name="$1" compose="$2"
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet';
     k.list(k.http('${name}', '${app_image}')
       + k.port(8080) + k.env({ WHOAMI_PORT_NUMBER: '8080' })
       + k.runAs(65532) + k.replicas(1) + k.probes('/') + k.hostUsers() ${compose})"
}

for pair in "bare:" "meshed:${compose}"; do
  name="${pair%%:*}"
  render_app "$name" "${pair#*:}" | kubectl apply --namespace="$ns" --filename=- >/dev/null 2>&1 \
    || fail "${name} did not apply"
  kubectl --namespace="$ns" rollout status "deployment/${name}" --timeout=300s >/dev/null \
    || fail "${name} never became Ready"
done

# Sanity: the meshed pod must actually carry a proxy, or the difference measures
# nothing. Both meshes inject it as a NATIVE SIDECAR — a restartable init
# container — so look in both container lists.
kubectl --namespace="$ns" get pods --selector=app.kubernetes.io/name=meshed \
  -o jsonpath='{.items[0].spec.containers[*].name} {.items[0].spec.initContainers[*].name}' \
  | grep -qw "$proxy_container" || fail "the meshed pod has no ${proxy_container}: there is nothing to measure"

# Re-submits a live pod as a dry-run CREATE and echoes the policies that warned.
# Everything the API server filled in is stripped: a pod carrying status,
# nodeName or a resourceVersion is rejected as invalid before any policy sees it,
# and that rejection is not a verdict. Dropping the labels also keeps the
# injector from injecting the probe a second time — its objectSelector needs the
# marker, and without it the probe carries exactly the containers the real pod
# already has.
policies_tripped() {
  local namespace="$1" selector="$2" spec="${work}/probe.json"
  kubectl --namespace="$namespace" get pods --selector="$selector" -o json 2>/dev/null \
    | jq '.items[0]
          | del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
                .metadata.ownerReferences, .metadata.generateName, .metadata.managedFields,
                .metadata.annotations, .metadata.labels, .spec.nodeName, .spec.tolerations,
                .spec.volumes, .spec.containers[].volumeMounts, .spec.initContainers[]?.volumeMounts)
          | .metadata.name = "bsi-probe"' >"$spec" 2>/dev/null
  [ -s "$spec" ] || return 1
  kubectl apply --namespace="$namespace" --dry-run=server --filename="$spec" 2>&1 >/dev/null \
    | grep -oP "ValidatingAdmissionPolicy '\K[^']+" | sort -u
}

policies_tripped "$ns" app.kubernetes.io/name=bare   >"${work}/bare.txt"   || fail "could not probe the bare pod"
policies_tripped "$ns" app.kubernetes.io/name=meshed >"${work}/meshed.txt" || fail "could not probe the meshed pod"

echo
echo "== bare pod =="
sed 's/^/   /' "${work}/bare.txt" || true
[ -s "${work}/bare.txt" ] || echo "   (none)"

echo "== meshed pod =="
sed 's/^/   /' "${work}/meshed.txt" || true
[ -s "${work}/meshed.txt" ] || echo "   (none)"

# Prints what $2 breaks that $1 does not, plus anything that went the other way
# — a policy the baseline breaks and the variant does not would mean the two
# probes measured different things, so it is reported rather than left unread.
difference() {
  echo "== $3 =="
  comm -13 "$1" "$2" >"${work}/added.txt"
  if [ -s "${work}/added.txt" ]; then
    sed 's/^/   + /' "${work}/added.txt"
  else
    echo "   nothing — the injected containers break no policy the workload did not already break"
  fi
  comm -23 "$1" "$2" | sed 's/^/   - (only in the baseline) /'
}

difference "${work}/bare.txt" "${work}/meshed.txt" "what the sidecar costs, with no CNI plugin"

# Installing the plugin's chart is not enough for either mesh: the control plane
# keeps injecting its init container until it is TOLD the plugin is there. Left
# out, the re-measurement repeats the first one and reads like a result — which
# is what the init-container guard below is for, and it has already caught it
# once.
enable_cni_istio() {
  helm upgrade --install istio-cni istio/cni \
    --version "$ISTIO_VERSION" --namespace istio-system --wait --timeout 5m >/dev/null 2>&1 \
  && helm upgrade istiod istio/istiod --version "$ISTIO_VERSION" --namespace istio-system \
    --reuse-values --set pilot.cni.enabled=true --wait --timeout 10m >/dev/null 2>&1
}
enable_cni_linkerd() {
  helm upgrade --install linkerd-cni linkerd-edge/linkerd2-cni \
    --version "$LINKERD_VERSION" --namespace linkerd-cni --create-namespace --wait --timeout 5m >/dev/null 2>&1 \
  && helm upgrade linkerd-control-plane linkerd-edge/linkerd-control-plane \
    --version "$LINKERD_VERSION" --namespace linkerd --reuse-values \
    --set cniEnabled=true --wait --timeout 10m >/dev/null 2>&1
}

echo
echo "== install the ${MESH} CNI plugin and re-measure =="
if "enable_cni_${MESH}"
then
  kubectl --namespace="$ns" rollout restart deployment/meshed >/dev/null
  kubectl --namespace="$ns" rollout status deployment/meshed --timeout=300s >/dev/null \
    || fail "the meshed app never came back after the CNI plugin went in"
  initnames="$(kubectl --namespace="$ns" get pods --selector=app.kubernetes.io/name=meshed \
    -o jsonpath='{.items[0].spec.initContainers[*].name}')"
  echo "   init containers now: ${initnames:-none}"
  # The whole claim is that the privileged init container is gone. Name it by the
  # mesh rather than by a pattern: an init list that merely lost a name for some
  # other reason must not read as the plugin working.
  case "$MESH" in
    istio) gone_container=istio-init ;;
    linkerd) gone_container=linkerd-init ;;
  esac
  if grep -qw "$gone_container" <<<"$initnames"; then
    echo "::warning::${gone_container} is still present with the CNI plugin installed — what follows is NOT the CNI case, do not read it as one"
  fi
  policies_tripped "$ns" app.kubernetes.io/name=meshed >"${work}/meshed-cni.txt" \
    || fail "could not probe the meshed pod after the CNI plugin went in"
  echo "== meshed pod, CNI plugin installed =="
  sed 's/^/   /' "${work}/meshed-cni.txt"
  [ -s "${work}/meshed-cni.txt" ] || echo "   (none)"
  difference "${work}/bare.txt" "${work}/meshed-cni.txt" "what the sidecar costs, with the CNI plugin"

  # Where the privilege WENT. The plugin does not remove the need to program a
  # pod's iptables — it moves that work out of every tenant pod and into one node
  # agent, which is privileged. Reporting the workload's improvement without this
  # would be reporting half a trade.
  echo
  echo "== the CNI node agent, which now does that work =="
  if policies_tripped "$cni_namespace" "$cni_selector" >"${work}/cni-agent.txt"; then
    sed 's/^/   /' "${work}/cni-agent.txt"
    [ -s "${work}/cni-agent.txt" ] || echo "   (none)"
  else
    echo "::warning::could not probe the CNI node agent — its cost stays unmeasured"
  fi
else
  echo "::warning::the Istio CNI plugin did not install — the CNI case stays unmeasured, which is not the same as measured and clear"
fi

echo
echo "== clean up =="
kubectl delete namespace "$ns" --wait=false >/dev/null 2>&1
kubectl delete --filename="${work}/policies.json" --ignore-not-found --wait=false >/dev/null 2>&1
for release in istio-cni istiod istio-base; do
  helm uninstall "$release" --namespace istio-system >/dev/null 2>&1 || true
done
helm uninstall linkerd-cni --namespace linkerd-cni >/dev/null 2>&1 || true
for release in linkerd-control-plane linkerd-crds; do
  helm uninstall "$release" --namespace linkerd >/dev/null 2>&1 || true
done
kubectl delete namespace istio-system linkerd linkerd-cni --wait=false >/dev/null 2>&1 || true
echo "done"
