# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The assertion suites plus the requiresService negative check. jsonnet has no
# try/catch, so the "compose an exposure onto a Service-less workload must
# fail" invariant can't live in an assertion file — it is exercised here.

# The k8s-libsonnet dependency floats at upstream HEAD (matching the JOI
# images); vendor it fresh so the suites test what clusters actually run.
jb install

# The workload stages below import kurly by its canonical path — the one JaaS
# resolves in a cluster — so resolve it locally through the vendor tree, as
# check-examples and check-catalog do.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

# Every tests/*_test.jsonnet is an assertion suite whose every field is a
# std.assertEqual (unit tests, plus the order-independence, invariant, and
# metamorphic batteries); assert all fields evaluate true.
for suite in tests/*_test.jsonnet; do
  jsonnet -J vendor "$suite" | jq -e 'to_entries | all(.value == true)' >/dev/null \
    || { echo "::error::assertion failed in $suite" >&2; exit 1; }
  echo "assertions passed: $suite"
done

# The requiresService assert must fire when an exposure is composed onto a
# workload with no Service.
if jsonnet -J vendor -e "local kurly = import 'main.libsonnet'; kurly.worker('w', 'img:1') + kurly.expose.ingress('h.example.com')" >/dev/null 2>&1; then
  echo "composing an exposure onto a worker rendered instead of failing" >&2
  exit 1
fi
echo "requiresService assert fired as expected"

# The exclusion assert must fire when two members of one exclusion group are
# composed — here two exposure recipes on one workload.
if jsonnet -J vendor -e "local kurly = import 'main.libsonnet'; kurly.http('h', 'img:1') + kurly.expose.ingress('h.example.com') + kurly.expose.gateway('h.example.com', 'gw')" >/dev/null 2>&1; then
  echo "composing two exposures rendered instead of failing" >&2
  exit 1
fi
echo "exposure exclusion assert fired as expected"

# Every workload that renders pods must let a consumer put labels and
# annotations on them: network-policy selectors, sidecar injection, log
# collection and scrape hints are the operator's business, not kurly's, and a
# workload that swallows them is unusable without forking it. The feature tests
# only prove the BASE KINDS honour podLabels — they say nothing about whether a
# given workload passes them through, which is the thing that actually breaks.
#
# The glob is the point: a workload added tomorrow is covered without editing
# this file. A workload rendering no pod template (a custom resource, whose pods
# belong to an operator) has nothing to assert here and is skipped by the same
# rule — those carry their own params and their own assertions in the suite.
echo "== every workload's pods accept labels and annotations =="
for stage in workloads/*/*.libsonnet; do
  # Decide the shape BEFORE composing anything: a custom-resource workload now
  # REJECTS a composed feature (it would silently do nothing), so composing one
  # here to find out would fail for the right reason and look like the wrong one.
  default="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')())")" \
    || { echo "::error::${stage}: does not render" >&2; exit 1; }
  templates="$(printf '%s' "$default" | jq '[.. | objects | select(has("template") and (.template | type == "object") and (.template | has("spec")))] | length')"
  if [ "$templates" = "0" ]; then
    echo "no pod template in $stage (a custom resource) — its own params carry pod metadata"
    continue
  fi

  rendered="$(
    jsonnet -J vendor -e \
      "local k = import 'github.com/metio/kurly/main.libsonnet';
       k.list((import '${stage}')()
         + k.podLabels({ 'kurly.test/label': 'set' })
         + k.podAnnotations({ 'kurly.test/annotation': 'set' }))"
  )" || { echo "::error::${stage}: failed to render with podLabels/podAnnotations" >&2; exit 1; }

  metas="$(printf '%s' "$rendered" | jq '[.. | objects | select(has("template") and (.template | type == "object") and (.template | has("spec"))) | .template.metadata]')"
  count="$(printf '%s' "$metas" | jq 'length')"
  missing="$(printf '%s' "$metas" | jq -r '[.[] | select((.labels["kurly.test/label"] != "set") or (.annotations["kurly.test/annotation"] != "set"))] | length')"
  if [ "$missing" != "0" ]; then
    echo "::error::${stage}: ${missing} of ${count} pod template(s) dropped podLabels/podAnnotations" >&2
    exit 1
  fi
  echo "pod labels and annotations reach every pod template in $stage"
done

# A PVC without a settable storage class is a workload that only runs on the
# cluster it was written for: classes differ per cluster, and the default one is
# rarely the right one for a database. Every workload that renders a PVC must
# therefore let a consumer choose the class — through a parameter, or by
# re-composing kurly.store, which a composable app always allows.
#
# The gate renders each workload TWICE: once as it ships, once with the class
# overridden through whichever mechanism it offers, and fails if the rendered
# PVC did not move. Rendering only the default would prove nothing — the field
# is absent either way when nobody sets it.
echo "== every workload's PVCs take a storage class =="
for stage in workloads/*/*.libsonnet; do
  # The mount path is the workload's own, so read it back from the default
  # render rather than assuming one: re-composing kurly.store needs it, and a
  # wrong path would mount a second volume instead of replacing the store.
  default="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')())")"
  claims="$(printf '%s' "$default" | jq '[.. | objects | select(.kind? == "PersistentVolumeClaim")] | length')"
  vct="$(printf '%s' "$default" | jq '[.. | objects | select(has("volumeClaimTemplates")) | .volumeClaimTemplates[]?] | length')"
  crstore="$(printf '%s' "$default" | jq '[.. | objects | select(has("storage") and (.storage | type == "object") and (.storage | has("size")))] | length')"
  if [ "$claims" = "0" ] && [ "$vct" = "0" ] && [ "$crstore" = "0" ]; then
    echo "no PVC in $stage"
    continue
  fi

  mount="$(printf '%s' "$default" | jq -r '[.. | objects | select(.name? == "store") | .mountPath?] | map(select(. != null)) | first // ""')"
  if [ -n "$mount" ]; then
    over="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')() + k.store('${mount}', '7Gi', storageClass='kurly-test-class'))")"
  else
    # A custom resource: its storage is a field of someone else's API, so the
    # class can only come from the workload's own parameter.
    over="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')(storageClass='kurly-test-class'))" 2>/dev/null || true)"
    if [ -z "$over" ]; then
      echo "::error::${stage}: renders a PVC but takes no storageClass parameter, and has no kurly.store to re-compose" >&2
      exit 1
    fi
  fi
  if ! printf '%s' "$over" | grep -q 'kurly-test-class'; then
    echo "::error::${stage}: renders a PVC whose storage class cannot be set" >&2
    exit 1
  fi
  echo "storage class is settable in $stage"
done

# A workload that renders no pod template authors a custom resource, and a kurly
# feature composed onto one CANNOT work: features write a hidden config that a
# BASE KIND reads, and there is no base here. Left alone that renders cleanly and
# does nothing — a green render and a cluster that behaves differently from the
# source, which is the worst failure this library has. Such a stage must reject a
# composed feature outright, while still honouring its own params and the raw `+`
# escape hatch (which touches no config).
echo "== custom-resource workloads reject features instead of swallowing them =="
for stage in workloads/*/*.libsonnet; do
  rendered="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')())")" \
    || { echo "::error::${stage}: does not render" >&2; exit 1; }
  templates="$(printf '%s' "$rendered" | jq '[.. | objects | select(has("template") and (.template | type == "object") and (.template | has("spec")))] | length')"
  [ "$templates" = "0" ] || continue   # a pod workload: features are its business

  if jsonnet -J vendor -e \
      "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')() + k.podLabels({ 'kurly.test/label': 'set' }))" >/dev/null 2>&1; then
    echo "::error::${stage}: renders no pod template, yet accepted kurly.podLabels() — the feature silently does nothing here; assert against a composed config instead" >&2
    exit 1
  fi
  # The escape hatch patches the resource itself and must keep working.
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')() + { kurlyTestProbe:: true })" >/dev/null 2>&1 \
    || { echo "::error::${stage}: rejects the raw + escape hatch, which touches no config" >&2; exit 1; }
  echo "features are rejected (and params/raw + still work) in $stage"
done

# A cluster is single-stack IPv4, single-stack IPv6, or dual-stack, and a Service
# pinning a family the cluster lacks is rejected. So when a consumer names the
# families, EVERY Service a workload renders must follow — a workload that writes
# a Service by hand (valkey/cache writes its primary one) otherwise keeps the
# cluster's default on that Service while the rest follow the consumer, and
# clients reach it over a family the workload does not speak elsewhere.
echo "== every Service follows the composed IP families =="
for stage in workloads/*/*.libsonnet; do
  default="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')())")" \
    || { echo "::error::${stage}: does not render" >&2; exit 1; }
  # Custom-resource workloads reject features by design, and their Services are
  # the operator's to create.
  [ "$(printf '%s' "$default" | jq '[.. | objects | select(.kind? == "Service")] | length')" != "0" ] || {
    echo "no Service in $stage"; continue; }

  strays="$(jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet';
     k.list((import '${stage}')() + k.ipFamilies(['IPv6'], 'SingleStack'))" \
    | jq -r '[.. | objects | select(.kind? == "Service") | select(.spec.ipFamilies != ["IPv6"]) | .metadata.name] | join(" ")')"
  if [ -n "$strays" ]; then
    echo "::error::${stage}: Service(s) ignored the composed IP families: ${strays}" >&2
    exit 1
  fi
  echo "every Service follows the composed IP families in $stage"
done

# Every container in a workload's pod must follow the composed uid — not just the
# one the recipe thinks of as its own. A uid written as a literal into an
# initContainer or a sidecar is beyond the reach of kurly.runAs() and the
# security profiles, and the pod then half-obeys the posture it was composed
# with. That is not cosmetic: OpenShift assigns each namespace an arbitrary uid
# range and REJECTS a container asking for anything else, so one stray literal
# makes the whole workload unrunnable there.
#
# 1000700000 is the shape of an OpenShift-assigned uid; nothing may keep a uid of
# its own choosing. Glob-driven, so a workload added tomorrow is covered.
echo "== every container follows the composed uid =="
for stage in workloads/*/*.libsonnet; do
  # A custom-resource workload rejects a composed feature on purpose (it would
  # otherwise vanish), and its containers are the operator's to create, so there
  # is no uid here to follow. Decide the shape before composing.
  default="$(jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')())")" \
    || { echo "::error::${stage}: does not render" >&2; exit 1; }
  if [ "$(printf '%s' "$default" | jq '[.. | objects | select(has("containers"))] | length')" = "0" ]; then
    echo "no containers in $stage (a custom resource) — the operator creates them"
    continue
  fi

  rendered="$(jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet';
     k.list((import '${stage}')() + k.runAs(1000700000))")" || {
    echo "::error::${stage}: failed to render with kurly.runAs()" >&2; exit 1; }

  strays="$(printf '%s' "$rendered" | jq -r '
    [.. | objects | select(has("containers") or has("initContainers"))
       | ((.initContainers // []) + (.containers // []))[]
       | select(.securityContext.runAsUser != null and .securityContext.runAsUser != 1000700000)
       | "\(.name)=\(.securityContext.runAsUser)"] | unique | join(" ")')"
  if [ -n "$strays" ]; then
    echo "::error::${stage}: container(s) keep a uid of their own after kurly.runAs(): ${strays}" >&2
    exit 1
  fi
  echo "every container follows the composed uid in $stage"
done

# Combinations that CANNOT start belong in the render, not in a CrashLoop. Each
# of these is a certain failure on a real cluster, and jsonnet has no try/catch,
# so an assert can only be observed by failing — which an assertion suite cannot
# express.
negative() { # <description> <expression that MUST fail to render>
  if jsonnet -J vendor -e "$2" >/dev/null 2>&1; then
    echo "$1: rendered instead of failing" >&2
    exit 1
  fi
  echo "assert fired as expected: $1"
}
positive() { # <description> <expression that MUST render>
  if ! jsonnet -J vendor -e "$2" >/dev/null 2>&1; then
    echo "$1: failed to render, but this combination is legitimate" >&2
    exit 1
  fi
  echo "renders as expected: $1"
}

K="local k = import 'github.com/metio/kurly/main.libsonnet';"
# uid 0 under runAsNonRoot: the kubelet refuses the container before it starts.
negative "runAsUser 0 contradicts runAsNonRoot" \
  "$K k.list(k.worker('w', 'img:1') + k.runAs(0))"
# Every honest way to actually run as root must still work, or the assert is a
# wall rather than a guard.
positive "runAs(0) + rootUser()" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.rootUser())"
positive "runAs(0) + security.baseline" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.security.baseline)"
positive "runAs(0) + security.privileged" "$K k.list(k.worker('w', 'img:1') + k.runAs(0) + k.security.privileged)"
# An arbitrary high uid is what OpenShift assigns; it must never trip the guard.
positive "an OpenShift-style arbitrary uid" "$K k.list(k.worker('w', 'img:1') + k.runAs(1000700000))"

# tik is one writer on one ReadWriteOnce volume; a second pod cannot attach it.
negative "tik scaled past its single writer" \
  "$K k.list((import 'workloads/tik/backend.libsonnet')() + k.replicas(3))"
positive "tik at its one replica" \
  "$K k.list((import 'workloads/tik/backend.libsonnet')() + k.replicas(1))"

# huge_pages=on without an allocation: PostgreSQL refuses to start, by design.
negative "huge_pages=on with no hugepages resource" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'on'})"
# Kubernetes rejects a pod whose hugepages request and limit differ.
negative "a hugepages request that differs from its limit" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(resources={limits: {'hugepages-2Mi': '2Gi'}, requests: {'hugepages-2Mi': '1Gi'}})"
positive "huge_pages=on with a matching allocation" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'on'}, resources={limits: {'hugepages-2Mi': '2Gi'}, requests: {'hugepages-2Mi': '2Gi'}})"
positive "huge_pages=try with no allocation" \
  "(import 'workloads/cnpg-cluster/cluster.libsonnet')(parameters={huge_pages: 'try'})"

# An app's memory flag and the container limit are two views of one number, and
# only the limit is enforced by the kernel. kurly.resources() REPLACES the limits
# object rather than merging, so composing it for an unrelated reason drops the
# derived limit and leaves the cache unbounded — and overriding it directly makes
# the flag and the cgroup disagree, which is an OOMKill at exactly the moment the
# cache fills.
negative "memcached with a hand-set memory limit" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=1024) + k.resources(limits={memory: '128Mi'}))"
negative "memcached losing its derived limit to an unrelated one" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=1024) + k.resources(limits={'ephemeral-storage': '1Gi'}))"
negative "dragonfly with a hand-set memory limit" \
  "$K k.list((import 'workloads/dragonfly/instance.libsonnet')(maxMemoryMB=2048, threads=4) + k.resources(limits={memory: '256Mi'}))"
# Sizing through the workload's own knob must keep working — the assert is a
# guard, not a wall.
positive "memcached sized through memoryMB" \
  "$K k.list((import 'workloads/memcached/cache.libsonnet')(memoryMB=4096))"
positive "dragonfly sized through maxMemoryMB" \
  "$K k.list((import 'workloads/dragonfly/instance.libsonnet')(maxMemoryMB=4096, threads=4))"

# Dragonfly exits at startup when maxmemory is under 256MiB per io thread, so
# the workload asserts the floor at render — the pod would otherwise CrashLoop
# with the reason buried in its log. An assert can only be observed by failing,
# which an assertion suite cannot express.
if jsonnet -J vendor -e "(import 'workloads/dragonfly/instance.libsonnet')(threads=4, maxMemoryMB=512)" >/dev/null 2>&1; then
  echo "dragonfly rendered below its memory floor instead of failing" >&2
  exit 1
fi
echo "dragonfly memory-floor assert fired as expected"

# Every image a workload renders must follow kurly.mirror onto the private
# registry. The assertion suite can only check mirror against apps it writes
# itself, which is precisely the blind spot that let kurly.image() redirect the
# valkey cache's main container while its initContainer and sidecar kept pulling
# from docker.io. So render each REAL workload through mirror and look for a
# public registry surviving anywhere in the output — that catches an image
# mirror cannot see (an initContainer, a grafted-on sidecar, a custom resource's
# own field) rather than only the fields it already knows about.
#
# The glob is the point: a workload added tomorrow is covered without editing
# this file, and a workload that hides an image somewhere new fails here.
#
# ConfigMap and Secret payloads are dropped first: mirror deliberately leaves
# application data alone, so a registry-looking string in there is not a leak.
echo "== mirror redirects every image in every workload =="
for stage in workloads/*/*.libsonnet; do
  leaked="$(
    jsonnet -J vendor -e \
      "local k = import 'github.com/metio/kurly/main.libsonnet'; k.mirror('registry.test', k.list((import '${stage}')()))" \
      | jq 'del(.. | objects | select(.kind == "ConfigMap" or .kind == "Secret") | .data)' \
      | grep -oE '(docker\.io|ghcr\.io|quay\.io|gcr\.io|registry\.k8s\.io|public\.ecr\.aws)/[^"]*' \
      | sort -u || true
  )"
  if [ -n "$leaked" ]; then
    echo "::error::${stage}: kurly.mirror left these on a public registry:" >&2
    printf '  %s\n' "$leaked" >&2
    exit 1
  fi
  echo "mirror covers every image in $stage"
done
