#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Shared helpers for the per-workload e2e scenarios (hack/smoke/scenario-*.sh).
# Each scenario is self-contained: it installs whatever operator it needs, renders
# the workload the way a consumer would, applies it to the current cluster (a kind
# cluster the e2e workflow owns), and waits for it to become healthy — proving the
# manifests kurly produces actually RUN, not just that they schema-validate.
set -euo pipefail

# kurly imports k8s-libsonnet (vendored fresh) and resolves its own canonical
# path through a vendor symlink, exactly as the render gates do.
kurly::vendor() {
  mkdir -p vendor/github.com/metio
  ln -sfn ../../.. vendor/github.com/metio/kurly
  # Idempotent: skip the (slow, and parallel-unsafe) jb install once the vendor
  # tree is populated, so many scenarios can share one pre-vendored checkout.
  [ -f vendor/.kurly-vendored ] && return 0
  jb install >/dev/null && touch vendor/.kurly-vendored
}

# Renders a workload stage (a function(params) app) to a kind: List, the way a
# consumer's JsonnetSnippet does. Extra Jsonnet composed onto the app is passed as
# $2 (e.g. "+ k.hostUsers()") — kind inside GitHub Actions cannot nest user
# namespaces, so kurly-pod workloads relax that one knob for the smoke.
kurly::render() {
  local stage="$1" extra="${2:-}"
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')() ${extra})"
}

# Creates a namespace idempotently.
kurly::namespace() {
  kubectl create namespace "$1" --dry-run=client --output=yaml | kubectl apply --filename=-
}

# CI-verifies a stage's declared minimum resources: renders it with the catalog's
# `minimumResources` as its requests AND (for memory + ephemeral-storage, the two
# that fail a pod rather than merely throttle it) its LIMITS, applies it to a
# throwaway namespace, and waits for its controller to roll out. If the declared
# minimum is too low the pod OOMs or is evicted and never becomes Ready, so this
# fails — turning the catalog number into a verified-sufficient floor rather than a
# guess. Called from a workload's OWN e2e scenario (gated on that workload's
# paths), so the check runs only when the workload it verifies changes.
#
#   kurly::verify_min_resources workloads/seaweedfs/server.libsonnet
kurly::verify_min_resources() {
  local stage="$1" extra="${2:-}"
  local mr cpu mem eph
  mr="$(jq -c --arg ip "github.com/metio/kurly/${stage}" \
    '.workloads[].stages[] | select(.importPath==$ip) | .minimumResources // empty' catalog/catalog.json)"
  [ -n "$mr" ] || { echo "::error::${stage} declares no minimumResources in the catalog"; return 1; }
  cpu="$(jq -r '.cpu' <<<"$mr")"; mem="$(jq -r '.memory' <<<"$mr")"; eph="$(jq -r '.ephemeralStorage' <<<"$mr")"
  local ns=min-resources
  kurly::namespace "$ns" >/dev/null
  echo "== verify ${stage} starts at its declared minimum (cpu=${cpu}, memory=${mem}, ephemeral-storage=${eph}) =="
  # requests carry the cpu floor; memory + ephemeral-storage are also limits, so an
  # insufficient number OOMs / evicts the pod instead of silently over-scheduling.
  # kind-in-CI cannot nest user namespaces, so hostUsers is relaxed (as elsewhere).
  local render="+ k.resources(requests={cpu: '${cpu}', memory: '${mem}', 'ephemeral-storage': '${eph}'}, limits={memory: '${mem}', 'ephemeral-storage': '${eph}'}) + k.hostUsers() ${extra}"
  kurly::render "$stage" "$render" | kubectl apply --namespace="$ns" --filename=-
  local ctrl
  for ctrl in $(kubectl --namespace="$ns" get deployment,statefulset --output=name); do
    kubectl --namespace="$ns" rollout status "$ctrl" --timeout=300s \
      || { echo "::error::${stage} did not become Ready at its declared minimum resources"; kurly::diagnose "$ns"; return 1; }
  done
  # Free the namespace so a second stage in the same scenario starts clean.
  kubectl delete namespace "$ns" --wait=false >/dev/null 2>&1 || true
  echo "ok: ${stage} starts at its declared minimum resources"
}

# Boots one workload stage on the live cluster the way a consumer would: render
# its defaults, apply, and wait for every controller it creates to become healthy
# — proving the stage RUNS, not merely that it schema-validates. hostUsers is
# relaxed because kind-in-CI cannot nest user namespaces; every other hardening
# knob the stage ships (read-only rootfs, dropped caps, seccomp, pinned uid) is
# still exercised. A CronJob stage carries no long-running controller, so it is
# triggered once as a Job and awaited. Extra Jsonnet composed onto the app is
# passed as $3 (e.g. a Secret-backed env the app needs to boot).
#
# Waits for a controller to become Ready, but FAILS FAST the moment one of its
# pods is clearly broken — CrashLoopBackOff, an image that will not pull
# (ImagePullBackOff/ErrImagePull), or repeated restarts — instead of blocking the
# full rollout timeout. Faster feedback that a version/manifest is broken, and it
# keeps the single-cluster e2e walk moving. Timeout via KURLY_ROLLOUT_TIMEOUT
# (seconds, default 300).
kurly::await_ready() {
  local ns="$1" ctrl="$2" timeout="${KURLY_ROLLOUT_TIMEOUT:-300}" deadline waitreason restarts
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if kubectl --namespace="$ns" rollout status "$ctrl" --timeout=4s >/dev/null 2>&1; then
      return 0
    fi
    # A pod stuck waiting on its image or crashing will never roll out — bail now.
    waitreason="$(kubectl --namespace="$ns" get pods \
      -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' 2>/dev/null \
      | grep -E 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName' | head -1 || true)"
    if [ -n "$waitreason" ]; then
      echo "::error::${ctrl}: pod broken (${waitreason})"; return 1
    fi
    restarts="$(kubectl --namespace="$ns" get pods \
      -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{end}' 2>/dev/null \
      | sort -rn | head -1 || true)"
    if [ "${restarts:-0}" -ge 3 ]; then
      echo "::error::${ctrl}: pod restarting repeatedly (restarts=${restarts})"; return 1
    fi
    sleep 4
  done
  echo "::error::${ctrl}: not Ready within ${timeout}s"; return 1
}

#   kurly::boot workloads/adguardhome/server.libsonnet kurly-adguardhome
kurly::boot() {
  local stage="$1" ns="$2" extra="${3:-}"
  kurly::namespace "$ns" >/dev/null
  echo "== boot ${stage} in ${ns} =="
  kurly::render "$stage" "+ k.hostUsers() ${extra}" | kubectl apply --namespace="$ns" --filename=-
  local ctrl found=0
  for ctrl in $(kubectl --namespace="$ns" get deployment,statefulset,daemonset --output=name 2>/dev/null); do
    found=1
    kurly::await_ready "$ns" "$ctrl" \
      || { echo "::error::${stage}: ${ctrl} never became Ready"; kurly::diagnose "$ns"; return 1; }
  done
  local cj
  for cj in $(kubectl --namespace="$ns" get cronjob --output=name 2>/dev/null); do
    found=1
    local job="smoke-${cj##*/}"
    kubectl --namespace="$ns" create job "$job" --from="$cj"
    kubectl --namespace="$ns" wait --for=condition=complete "job/${job}" --timeout=300s \
      || { echo "::error::${stage}: ${cj} test job did not complete"; kurly::diagnose "$ns"; return 1; }
  done
  [ "$found" = 1 ] || { echo "::error::${stage}: rendered no runnable controller"; return 1; }
  echo "ok: ${stage} is healthy on a live cluster"
}

# A single shared test password every provisioned dependency and minted Secret
# uses, so an app's DB_PASSWORD Secret key matches the database it connects to.
KURLY_E2E_PASSWORD="kurlye2epassword"

# Mints the Secret a stage reads, from the catalog's per-stage `secretKeys`
# contract: each key is generated as a password (the shared test password, so it
# matches the provisioned database), a fixed hex string, or its declared literal.
# kurly authors no Secret itself — a consumer supplies it — so the e2e supplies a
# throwaway one shaped exactly like the catalog says the app needs.
#   kurly::secret <ns> <secret-name> <stage-file>
kurly::secret() {
  local ns="$1" name="$2" stage="$3"
  local keys
  keys="$(jq -c --arg ip "github.com/metio/kurly/${stage}" \
    '.workloads[].stages[] | select(.importPath==$ip) | .secretKeys // []' catalog/catalog.json)"
  [ "$keys" != "[]" ] && [ -n "$keys" ] || return 0
  # The workload id, so a connection-URL key can be built from the throwaway
  # postgres/valkey this app's deps were provisioned under (the <id>-db-rw /
  # <id>-cache-headless convention in kurly::provision_deps).
  local id; id="$(sed -E 's#^workloads/([^/]+)/.*#\1#' <<<"$stage")"
  local args=() k gen val
  while read -r k; do
    gen="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .generate' <<<"$keys")"
    case "$gen" in
      password) val="$KURLY_E2E_PASSWORD" ;;
      hex)
        # A random hex string of the DECLARED length — apps like Django reject a
        # short or low-entropy SECRET_KEY (security.W009), so honour the length.
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 64' <<<"$keys")"
        val="$(head -c "$len" /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c "1-${len}")"
        ;;
      # A url-safe base64 key of the declared BYTE length — what Fernet and the
      # libraries that wrap it require; a hex string of the same length is rejected.
      base64)
        len="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .length // 32' <<<"$keys")"
        val="$(head -c "$len" /dev/urandom | base64 | tr '+/' '-_' | tr -d '\n')"
        ;;
      literal) val="$(jq -r --arg k "$k" '.[] | select(.key==$k) | .value' <<<"$keys")" ;;
      # Composite connection strings some apps read as a single secret (Prisma's
      # DATABASE_URL, etc.), built from the provisioned dependency.
      # The throwaway postgres serves plaintext, and a client that defaults to
      # sslmode=require (Go's pq, among others) fails its first query without this.
      postgresUrl) val="postgresql://${id}:${KURLY_E2E_PASSWORD}@${id}-db-rw:5432/${id}?sslmode=disable" ;;
      redisUrl) val="redis://${id}-cache-headless:6379" ;;
      *) val="$KURLY_E2E_PASSWORD" ;;
    esac
    args+=("--from-literal=${k}=${val}")
  done < <(jq -r '.[].key' <<<"$keys")
  kubectl --namespace="$ns" create secret generic "$name" "${args[@]}" \
    --dry-run=client --output=yaml | kubectl apply --filename=-
}

# A throwaway PostgreSQL for an app's e2e: a single Deployment + Service at the
# service name the app defaults to (so it connects with no param override), seeded
# with the app's database, user, and the shared test password. Not hardened (it is
# a disposable dependency, torn down with the cluster), so it boots on kind's
# default posture without relaxation. Extra "-c name=value" server settings and a
# custom image (e.g. one carrying an extension) may be passed as $5 / $6.
#   kurly::postgres <ns> <service> <db> <user> [image] [extraArgs]
kurly::postgres() {
  local ns="$1" svc="$2" db="$3" user="$4" image="${5:-docker.io/library/postgres:17}" extra="${6:-}"
  echo "== provision postgres ${svc} (db=${db}, user=${user}) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: postgres
          image: ${image}
          args: ["postgres"${extra:+, ${extra}}]
          env:
            - { name: POSTGRES_DB, value: "${db}" }
            - { name: POSTGRES_USER, value: "${user}" }
            - { name: POSTGRES_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            - { name: PGDATA, value: /var/lib/postgresql/data/pgdata }
          ports: [{ containerPort: 5432 }]
          volumeMounts: [{ name: data, mountPath: /var/lib/postgresql/data }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# A throwaway Valkey (Redis) for an app's e2e, at the service name the app
# defaults to. Authless (matches the app defaulting to no REDIS_PASSWORD).
#   kurly::cache <ns> <service>
kurly::cache() {
  local ns="$1" svc="$2"
  echo "== provision valkey ${svc} =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: valkey
          image: docker.io/valkey/valkey:8
          ports: [{ containerPort: 6379 }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 6379, targetPort: 6379 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# A throwaway MariaDB for an app's e2e, at the service name the app defaults to,
# seeded with the app's database, user, and the shared test password (and the
# same password for root). Many self-hosted apps need MySQL/MariaDB rather than
# PostgreSQL.
#   kurly::mysql <ns> <service> <db> <user>
kurly::mysql() {
  local ns="$1" svc="$2" db="$3" user="$4"
  echo "== provision mariadb ${svc} (db=${db}, user=${user}) =="
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: ${svc}, labels: { app: ${svc} } }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${svc} } }
  template:
    metadata: { labels: { app: ${svc} } }
    spec:
      containers:
        - name: mariadb
          image: docker.io/library/mariadb:11
          env:
            - { name: MARIADB_ROOT_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
            - { name: MARIADB_DATABASE, value: "${db}" }
            - { name: MARIADB_USER, value: "${user}" }
            - { name: MARIADB_PASSWORD, value: "${KURLY_E2E_PASSWORD}" }
          ports: [{ containerPort: 3306 }]
          volumeMounts: [{ name: data, mountPath: /var/lib/mysql }]
      volumes: [{ name: data, emptyDir: {} }]
---
apiVersion: v1
kind: Service
metadata: { name: ${svc} }
spec:
  selector: { app: ${svc} }
  ports: [{ port: 3306, targetPort: 3306 }]
EOF
  kubectl --namespace="$ns" rollout status "deployment/${svc}" --timeout=180s
}

# Fast check for an operator/custom-resource workload (no image of its own): it
# installs the operator's CRDs and validates the rendered custom resource against
# the real schema with a server-side dry-run — catching a version or field the
# operator would reject, in seconds, without waiting for a full cluster to
# reconcile. Standing up the real database/search/identity cluster is the deeper
# tier that comes later; this is the fast "is this version's manifest broken"
# signal the auto-merge net needs.
#   kurly::validate_cr <ns> <stage-file> <crd-url>...
kurly::validate_cr() {
  local ns="$1" stage="$2"; shift 2
  local url names attempt
  for url in "$@"; do
    echo "== install CRD ${url##*/} =="
    mapfile -t names < <(kubectl apply --server-side --force-conflicts --filename="$url" --output=name)
    printf '%s\n' "${names[@]}"
    # A freshly applied CRD is not servable until the apiserver establishes it, so a
    # dry-run right after the apply fails with "no matches for kind".
    [ "${#names[@]}" -gt 0 ] \
      && kubectl wait --for=condition=Established --timeout=120s "${names[@]}" >/dev/null 2>&1
  done
  # kubectl caches discovery per cluster; drop it so the new group is visible.
  rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true
  kurly::namespace "$ns" >/dev/null
  echo "== validate the rendered custom resource against the operator schema =="
  for attempt in 1 2 3 4 5; do
    if kurly::render "$stage" \
      | kubectl apply --namespace="$ns" --server-side --dry-run=server --filename=-; then
      echo "ok: ${stage} validates against the operator schema on a live cluster"
      return 0
    fi
    echo "validate attempt ${attempt} failed — retrying"
    sleep 5
  done
  echo "::error::${stage}: the custom resource was rejected by the operator schema"
  return 1
}

# Frees everything a workload's fast + deep checks created, so the shared single
# cluster does not accumulate pods across the walk. Deletes the workload's
# namespaces (kurly-<id>, kurly-<id>-<stage>, kurly-deep-<id>) and the deep
# check's cluster-scoped RoleBinding, then waits briefly for termination so the
# next workload starts on a drained cluster. Best-effort — a slow finalizer never
# fails the run. Installed operators/CRDs are left in place (harmless, and
# re-running their install is idempotent).
kurly::cleanup_workload() {
  local id="$1" nss
  mapfile -t nss < <(kubectl get namespace --output=name 2>/dev/null \
    | sed 's#namespace/##' | grep -E "^kurly-(deep-)?${id}(-|\$)" || true)
  # --interactive=false: kubectl prompts for delete confirmation and reads EOF as
  # "no" in a non-interactive shell, silently cancelling the delete otherwise.
  kubectl delete clusterrolebinding "stageset-deployer-kurly-deep-${id}" --interactive=false --ignore-not-found >/dev/null 2>&1 || true
  [ "${#nss[@]}" -gt 0 ] || return 0
  echo "== cleanup ${id}: deleting namespaces ${nss[*]} =="
  # A blocking delete (kubectl's default --wait) returns only once the namespaces
  # and everything in them are gone, so the next workload starts on a drained
  # cluster; the timeout caps a stuck finalizer rather than hanging the walk.
  kubectl delete namespace "${nss[@]}" --interactive=false --timeout=180s >/dev/null 2>&1 || true
}

# Extracts a stage parameter's simple quoted default (dbHost='x' -> x); empty when
# the default is a computed expression rather than a literal.
kurly::_param() { grep -oE "^[[:space:]]*$2='[^']*'" "$1" 2>/dev/null | head -1 | sed -E "s/.*='([^']*)'.*/\1/" || true; }

# The workloads a PR changed relative to the default branch — one per line. On a
# manual dispatch (no base to diff), or when $WORKLOADS is set explicitly, that
# selection wins instead. This is what keeps the single pipeline short: only
# changed workloads run.
kurly::changed_workloads() {
  if [ -n "${WORKLOADS:-}" ]; then
    printf '%s\n' $WORKLOADS
    return 0
  fi
  local base="origin/${BASE_REF:-main}"
  git diff --name-only "$base"...HEAD 2>/dev/null \
    | grep -oE '^workloads/[a-z0-9-]+/' | sed -E 's#workloads/([^/]+)/#\1#' | sort -u
}

# Provisions a workload's declared dependencies + Secret into <ns>, reading the
# catalog and the stage's default connection params at runtime — the same wiring
# the generated fast scenario bakes in, reusable by the deep check.
kurly::provision_deps() {
  local id="$1" ns="$2" primary st f dbHost dbName dbUser redisHost secretName
  primary="workloads/${id}/$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|.stages[0].id' catalog/catalog.json).libsonnet"
  if [ "$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|if .requires.database then 1 else 0 end' catalog/catalog.json)" = 1 ]; then
    dbName="$(kurly::_param "$primary" dbName)"; [ -n "$dbName" ] || dbName="$(kurly::_param "$primary" database)"; [ -n "$dbName" ] || dbName="$id"
    dbUser="$(kurly::_param "$primary" dbUser)"; [ -n "$dbUser" ] || dbUser="$id"
    # MySQL/MariaDB apps read port 3306 (postgres apps 5432); provision the engine
    # the app actually connects to, at the host it defaults to.
    if grep -qE "3306|mariadb|mysql" "$primary" 2>/dev/null; then
      dbHost="$(kurly::_param "$primary" dbHost)"; [ -n "$dbHost" ] || dbHost="${id}-db"
      kurly::mysql "$ns" "$dbHost" "$dbName" "$dbUser"
    else
      dbHost="$(kurly::_param "$primary" dbHost)"; [ -n "$dbHost" ] || dbHost="${id}-db-rw"
      kurly::postgres "$ns" "$dbHost" "$dbName" "$dbUser"
    fi
  fi
  if [ "$(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|if .requires.cache then 1 else 0 end' catalog/catalog.json)" = 1 ]; then
    redisHost="$(kurly::_param "$primary" redisHost)"; [ -n "$redisHost" ] || redisHost="${id}-cache-headless"
    kurly::cache "$ns" "$redisHost"
  fi
  for st in $(jq -r --arg id "$id" '.workloads[]|select(.id==$id)|.stages[].id' catalog/catalog.json); do
    f="workloads/${id}/${st}.libsonnet"
    secretName="$(kurly::_param "$f" secretName)"; [ -n "$secretName" ] || secretName="$id"
    kurly::secret "$ns" "$secretName" "$f"
  done
}

# Deep check: deliver a workload through the real production path — build + push
# its source image, let Flux pull it (OCIRepository), JaaS render it
# (JsonnetSnippet), and stageset-controller apply it (StageSet) — then wait for
# its controllers to roll out. The flux/jaas/stageset stack (latest of each) and
# the kurly library image are installed/published once by the pipeline before the
# loop. A custom-resource workload has no controller of its own, so it is
# fast-check only and this is a no-op.
kurly::deep() {
  local id="$1" ns="kurly-deep-${id}" st f snip ctrl kind name apiv
  # Skip workloads whose stages render only a custom resource (no controller).
  if ! kurly::render "workloads/${id}/$(jq -r --arg i "$id" '.workloads[]|select(.id==$i)|.stages[0].id' catalog/catalog.json).libsonnet" "+ k.hostUsers()" 2>/dev/null \
      | jq -e '.items[] | select(.kind=="Deployment" or .kind=="StatefulSet" or .kind=="DaemonSet")' >/dev/null 2>&1; then
    echo "== deep: ${id} renders no standard controller (operator/CR) — fast check only =="
    return 0
  fi
  echo "== DEEP ${id}: deliver through Flux -> JaaS -> stageset =="
  kurly::namespace "$ns" >/dev/null
  kurly::grant_tenant_publish_rbac "$ns"
  # The ServiceAccount the StageSet applies its manifests as (cluster-admin — e2e
  # simplicity, a throwaway cluster).
  kubectl --namespace="$ns" create serviceaccount stageset-deployer --dry-run=client --output=yaml | kubectl apply --filename=-
  kubectl create clusterrolebinding "stageset-deployer-${ns}" --clusterrole=cluster-admin \
    --serviceaccount="${ns}:stageset-deployer" --dry-run=client --output=yaml | kubectl apply --filename=-
  kurly::provision_deps "$id" "$ns"
  kurly::publish_images "$id"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec: { interval: 1h, url: oci://ghcr.io/metio/joi-jsonnet-libs-k8s-libsonnet, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec: { sourceRef: { kind: OCIRepository, name: k8s-libsonnet } }
EOF
  kurly::emit_oci_library "$ns" kurly kurly
  kurly::emit_oci_library "$ns" "kurly-${id}" "kurly-${id}"
  kurly::wait_ocirepository "$ns" k8s-libsonnet
  kurly::wait_ocirepository "$ns" kurly
  kurly::wait_ocirepository "$ns" "kurly-${id}"

  for st in $(jq -r --arg i "$id" '.workloads[]|select(.id==$i)|.stages[].id' catalog/catalog.json); do
    f="workloads/${id}/${st}.libsonnet"
    snip="${id}-${st}"
    # Discover the stage's primary controller so the StageSet's readyChecks and
    # version source name a real object.
    ctrl="$(kurly::render "$f" "+ k.hostUsers()" | jq -c '[.items[] | select(.kind=="Deployment" or .kind=="StatefulSet" or .kind=="DaemonSet")][0]')"
    [ "$ctrl" != null ] && [ -n "$ctrl" ] || { echo "== deep: ${st} has no controller, skipping stage =="; continue; }
    kind="$(jq -r '.kind' <<<"$ctrl")"; name="$(jq -r '.metadata.name' <<<"$ctrl")"; apiv="$(jq -r '.apiVersion' <<<"$ctrl")"
    kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ${snip}, namespace: ${ns} }
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local stage = import 'github.com/metio/kurly/${f}';
      local rendered = kurly.list(stage() + kurly.hostUsers());
      rendered { items: [ item { metadata+: { namespace: '${ns}' } } for item in rendered.items ] }
EOF
    kurly::wait_ready jsonnetsnippet "$snip" 60
    kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ${snip}, namespace: ${ns} }
spec:
  interval: 1m
  serviceAccountName: stageset-deployer
  version:
    fromObject: { stage: ${st}, apiVersion: ${apiv}, kind: ${kind}, name: ${name} }
  stages:
    - name: ${st}
      sourceRef: { name: ${snip} }
      readyChecks:
        checks:
          - { apiVersion: ${apiv}, kind: ${kind}, name: ${name}, namespace: ${ns} }
EOF
    kurly::wait_ready stageset "$snip" 90
    kubectl --namespace="$ns" rollout status "${kind,,}/${name}" --timeout=300s \
      || { echo "::error::deep ${id}: ${kind}/${name} never rolled out via stageset"; kurly::diagnose "$ns"; kurly::diagnose_pipeline "$ns"; return 1; }
  done
  echo "ok: ${id} delivered end-to-end through Flux -> JaaS -> stageset"
}

# Blocks until a resource's Ready condition is true (or times out loudly).
kurly::wait_ready() {
  local res="$1" name="$2" tries="${3:-60}" i
  for i in $(seq 1 "$tries"); do
    [ "$(kubectl get "$res" "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)" = True ] \
      && return 0
    sleep 3
  done
  echo "::error::${res}/${name} never became Ready"; return 1
}

# Dumps everything useful about a namespace on failure, grouped in the log.
kurly::diagnose() {
  local ns="$1"
  echo "::group::diagnostics ($ns)"
  kubectl --namespace="$ns" get all,pvc,endpoints 2>/dev/null || true
  kubectl --namespace="$ns" get pods --show-labels 2>/dev/null || true
  kubectl --namespace="$ns" describe pods 2>/dev/null | tail -120 || true
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=kurly --all-containers=true --tail=100 2>/dev/null || true
  # A container in CrashLoopBackOff has no live logs — the output that explains why
  # it died belongs to the previous instance.
  echo "--- previous container logs ---"
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=kurly --all-containers=true --tail=100 --previous 2>/dev/null || true
  kubectl --namespace="$ns" get events --sort-by=.lastTimestamp 2>/dev/null | tail -40 || true
  echo "::endgroup::"
}

# Dumps the Flux + JaaS + stageset pipeline objects on failure. The Ready
# condition message of the JsonnetSnippet and the StageSet is where import,
# render, and apply errors surface, so print each one's full status.
kurly::diagnose_pipeline() {
  local ns="$1"
  echo "::group::pipeline diagnostics ($ns)"
  kubectl --namespace="$ns" get gitrepository,ocirepository,jsonnetlibrary,jsonnetsnippet,externalartifact,stageset,stageinventory -o wide 2>/dev/null || true
  echo "--- JsonnetSnippet status ---"
  kubectl --namespace="$ns" get jsonnetsnippet valkey -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" describe jsonnetsnippet valkey 2>/dev/null | tail -40 || true
  echo "--- StageSet status ---"
  kubectl --namespace="$ns" get stageset valkey -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" describe stageset valkey 2>/dev/null | tail -40 || true
  # Did the applied workload objects land ANYWHERE? (A kind:List that the applier
  # never expands, or objects placed in another namespace, both read as NotFound
  # to the readyChecks.) And what did stageset record as applied?
  echo "--- valkey workload objects across all namespaces ---"
  kubectl get deployments,statefulsets,services,pods --all-namespaces 2>/dev/null \
    | grep -i valkey || echo "(no valkey workload objects found in any namespace)"
  echo "--- StageInventory (what stageset applied) ---"
  kubectl --namespace="$ns" get stageinventory -o yaml 2>/dev/null | grep -iE "kind:|name:|namespace:|apiVersion:" | head -40 || true
  # The controllers' own pods and logs — where a hang that never writes a CR
  # condition (an OOMKill, a crash, a stuck fetch) actually shows up.
  echo "--- JaaS operator (pods + logs) ---"
  kubectl --namespace=jaas-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=jaas-system logs --selector=app.kubernetes.io/instance=jaas \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
  echo "--- stageset-controller (pods + logs) ---"
  kubectl --namespace=stageset-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=stageset-system logs --selector=app.kubernetes.io/instance=stageset \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
  echo "::endgroup::"
}

# Installs the FULL Flux suite (always the latest release) and opens the
# source-controller artifact port cluster-wide. JaaS needs the ExternalArtifact
# kind, which ships in source-controller v1.7.0+ (Flux v2.7.0+).
kurly::install_flux() {
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r .tag_name 2>/dev/null || true)"
  [ -n "$ver" ] && [ "$ver" != "null" ] || ver="v2.7.0"
  echo "== install Flux ${ver} =="
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "https://github.com/fluxcd/flux2/releases/download/${ver}/install.yaml"
  kubectl -n flux-system rollout status deploy/source-controller --timeout=300s

  # Flux's default `allow-egress` NetworkPolicy admits ingress to source-controller
  # only from pods inside flux-system, and `allow-scraping` opens only the metrics
  # port (8080). The artifact HTTP server listens on 9090, so an operator running
  # outside flux-system can't fetch artifacts once the CNI enforces NetworkPolicies
  # (recent kindnet does; older kindnet treated them as no-ops). Open the artifact
  # port cluster-wide so the operator — and any tenant namespace — can reach it.
  kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-artifact-fetch
  namespace: flux-system
spec:
  podSelector:
    matchLabels:
      app: source-controller
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - port: 9090
          protocol: TCP
EOF
}

# Installs JaaS from its released chart (latest). The webhook is off to avoid a
# cert-manager dependency; the bundled shared libraries are off because kind lacks
# the ImageVolume feature gate they mount through.
kurly::install_jaas() {
  echo "== install JaaS (helm) =="
  # The chart's default 64Mi is far too small to render k8s-libsonnet (go-jsonnet
  # peaks at hundreds of MB), so the operator OOMKills on the first reconcile —
  # give it room.
  helm upgrade --install jaas oci://ghcr.io/metio/helm-charts/jaas \
    --namespace jaas-system --create-namespace \
    --set operator.enabled=true \
    --set operator.defaultServiceAccount=default \
    --set operator.webhook.enabled=false \
    --set libraries.grafonnet.enabled=false \
    --set libraries.docsonnet.enabled=false \
    --set libraries.xtd.enabled=false \
    --set resources.memory=2Gi \
    --wait --timeout 5m
  kubectl -n jaas-system rollout status deploy \
    --selector app.kubernetes.io/name=jaas --timeout=300s || true
}

# Installs the stageset-controller from its released chart (latest).
kurly::install_stageset() {
  echo "== install stageset-controller (helm) =="
  helm upgrade --install stageset oci://ghcr.io/metio/helm-charts/stageset-controller \
    --namespace stageset-system --create-namespace \
    --wait --timeout 5m
}

# grant_tenant_publish_rbac <ns> [sa] — grant the tenant ServiceAccount (default
# "default") the RBAC the operator needs while impersonating it to publish: get /
# list / watch / create / update / patch / delete the snippet's ExternalArtifact
# and write its status. The operator acts AS the tenant SA (no `impersonate` verb
# on its own SA), so without this every reconcile fails RBACDenied at the publish
# step and the snippet never goes Ready.
kurly::grant_tenant_publish_rbac() {
  local ns=$1 sa=${2:-default}
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
rules:
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["externalartifacts", "externalartifacts/status"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # The operator impersonates the tenant SA to READ the JsonnetLibrary resources
  # the snippet references, so grant read access to them too. (Inline-only
  # snippets don't need this; ours references the kurly + k8s-libsonnet libs.)
  - apiGroups: ["jaas.metio.wtf"]
    resources: ["jsonnetlibraries"]
    verbs: ["get", "list", "watch"]
  # A source-backed JsonnetLibrary (ours: k8s-libsonnet from an OCIRepository)
  # makes the operator read that source CR for its artifact URL, so grant read on
  # the Flux source kinds (git/bucket too, so the helper generalizes).
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["ocirepositories", "gitrepositories", "buckets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
subjects:
  - { kind: ServiceAccount, name: ${sa}, namespace: ${ns} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: jaas-tenant-publish }
EOF
}

# The in-cluster registry that serves the branch-built images to Flux. The
# stageset scenarios consume kurly through the SAME path a real deployment does —
# an OCIRepository — instead of an inline JsonnetLibrary, so the image packaging
# (the Containerfiles, the single layer, the vendor-tree layout) is exercised on
# every run, not just at release. Building from the checkout keeps the "tests the
# exact branch" property the inline library had.
#
# One registry, reached two ways: the host pushes over a NodePort the e2e
# workflow maps to localhost:5001 (registry:true), and source-controller pulls
# over the ClusterIP by DNS. Plain HTTP, so the host push relies on Docker
# trusting localhost and the OCIRepository sets `insecure: true`.
KURLY_REGISTRY_PUSH="localhost:5001"
KURLY_REGISTRY_PULL="registry.registry.svc.cluster.local:5000"
KURLY_IMAGE_TAG="e2e"

# Deploys registry:2 in its own namespace with a fixed NodePort, and waits for it
# to serve. The NodePort (30500) is the one the workflow's kind config maps to the
# host, so a scenario that calls this MUST run under a `registry: true` e2e job.
kurly::install_registry() {
  echo "== install in-cluster registry =="
  kubectl apply --filename=- <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: registry }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: registry, namespace: registry }
spec:
  replicas: 1
  selector: { matchLabels: { app: registry } }
  template:
    metadata: { labels: { app: registry } }
    spec:
      containers:
        - name: registry
          image: docker.io/library/registry:2
          ports:
            - { containerPort: 5000 }
---
apiVersion: v1
kind: Service
metadata: { name: registry, namespace: registry }
spec:
  type: NodePort
  selector: { app: registry }
  ports:
    - { port: 5000, targetPort: 5000, nodePort: 30500, protocol: TCP }
EOF
  kubectl -n registry rollout status deploy/registry --timeout=180s
}

# Builds the branch's library and workload images and pushes them to the registry
# through the host port-map. Usage: kurly::publish_images <workload>...
# The library is always published (every stage imports it); each named workload's
# source image is published too. Push is retried, since the NodePort route can lag
# the pod becoming Ready.
kurly::publish_images() {
  local push
  _push() {
    local ref="$1" i
    for i in $(seq 1 12); do
      docker push "$ref" && return 0
      echo "push $ref failed (attempt $i) — retrying"
      sleep 5
    done
    echo "push $ref never succeeded" >&2
    return 1
  }
  echo "== build and push the kurly library image =="
  push="${KURLY_REGISTRY_PUSH}/kurly:${KURLY_IMAGE_TAG}"
  docker build --file Containerfile --tag "$push" .
  _push "$push"
  local wl
  for wl in "$@"; do
    echo "== build and push the ${wl} workload image =="
    push="${KURLY_REGISTRY_PUSH}/kurly-${wl}:${KURLY_IMAGE_TAG}"
    docker build --file workload.Containerfile --build-arg "WORKLOAD=${wl}" --tag "$push" .
    _push "$push"
  done
}

# Emits an OCIRepository (pulling from the in-cluster registry, insecure HTTP) and
# the JsonnetLibrary that sources it. Usage:
#   kurly::emit_oci_library <ns> <library-name> <image-repo>
# e.g. `kurly::emit_oci_library cache kurly kurly` and
#      `kurly::emit_oci_library cache kurly-valkey kurly-valkey`.
kurly::emit_oci_library() {
  local ns="$1" name="$2" repo="$3"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: ${name}, namespace: ${ns} }
spec:
  interval: 1h
  insecure: true
  url: oci://${KURLY_REGISTRY_PULL}/${repo}
  ref: { tag: ${KURLY_IMAGE_TAG} }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: ${name}, namespace: ${ns} }
spec:
  sourceRef: { kind: OCIRepository, name: ${name} }
EOF
}

# Blocks until an OCIRepository advertises a fetched artifact (or fails loudly).
kurly::wait_ocirepository() {
  local ns="$1" name="$2" i
  for i in $(seq 1 60); do
    [ -n "$(kubectl --namespace="$ns" get ocirepository/"$name" -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
      && { echo "ocirepository/${name} has an artifact"; return 0; }
    sleep 3
  done
  echo "ocirepository/${name} never advertised an artifact" >&2
  return 1
}
