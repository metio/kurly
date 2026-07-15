// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// valkey (in-memory cache, zero-downtime version hand-off) — a Valkey cache that
// upgrades its version without downtime or data loss, on the OFFICIAL upstream
// image and with no orchestrator: the hand-off lives entirely in the pod's own
// manifests, so a plain `kubectl apply`, a Helm upgrade, or a stageset roll all
// trigger it identically.
//
// The mechanism (a manifests-only transcription of the same replication hand-off
// a custom image would bake in):
//   - a headless Service lets pods find each other by DNS;
//   - a RollingUpdate with maxSurge=1 starts the new-version pod BESIDE the old;
//   - an initContainer discovers the running peer and writes a config that
//     REPLICAOFs it, so the new pod boots as a secondary and syncs the dataset;
//   - readiness is `master_link_status:up`, so the new pod is Ready only once in
//     sync — which is when Kubernetes removes the old one;
//   - the old pod's preStop runs Valkey's own atomic `failover`, promoting the
//     new pod before it terminates. No lost writes, no split brain.
//
// Persistence is off (a cache): the dataset moves by replication on every
// rollover, not through a volume. Clients connect at valkey-headless:6379.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline rewrites 'dev' to the calver.
local version = 'dev';

function(
  image='docker.io/valkey/valkey:8.1.8',
  maxMemory='256mb',
  // The sidecar that labels the primary pod — a maintained Alpine image carrying
  // kubectl plus busybox `nc` and `sh` (the role probe needs neither bash nor a
  // Valkey client); overridable. Only this workload's plumbing runs it — the
  // Valkey data container stays the stock image.
  kubectlImage='docker.io/alpine/k8s:1.36.2',
)
  local headless = 'valkey-headless';
  local roleLabel = 'kurly.dev/valkey-role';

  // Discover a running peer via the headless Service and, when one is found,
  // write a config that replicates it. The whole server config is generated
  // here so the stock image needs no baked-in scripts.
  local initScript = |||
    set -eu
    my_ip="$(hostname -i | awk '{print $1}')"
    primary="$(getent hosts %(headless)s | awk '{print $1}' | grep -v "^${my_ip}$" | head -1)"
    {
      echo 'dir /gen'
      echo 'save ""'
      echo 'appendonly no'
      echo 'maxmemory %(maxMemory)s'
      echo 'maxmemory-policy allkeys-lru'
      if [ -n "$primary" ]; then echo "replicaof ${primary} 6379"; else echo '# no peer: starting as primary'; fi
    } > /gen/valkey.conf
    cat /gen/valkey.conf
  ||| % { headless: headless, maxMemory: maxMemory };

  // If this pod is the primary with a connected replica, hand off with Valkey's
  // own atomic failover before terminating; a secondary (or a lone primary)
  // exits at once.
  local preStopScript = |||
    valkey-cli role | grep -q slave && exit 0
    valkey-cli info replication | grep -q 'connected_slaves:0' && exit 0
    valkey-cli failover
    i=0
    while [ "$i" -lt 60 ]; do
      valkey-cli role | grep -q slave && exit 0
      i=$((i + 1))
      sleep 1
    done
  |||;

  local hardened = {
    readOnlyRootFilesystem: true,
    allowPrivilegeEscalation: false,
    runAsNonRoot: true,
    runAsUser: 999,
    capabilities: { drop: ['ALL'] },
    seccompProfile: { type: 'RuntimeDefault' },
  };

  // The role labeler: probe the local Valkey's replication role with busybox
  // `nc` (no bash, no Valkey client) and keep this pod's `roleLabel` in sync —
  // set to `primary` on the master, removed on a replica. A direct merge `patch`
  // (never `kubectl label`, which GETs first) writes the label, so the sidecar's
  // Role needs only `patch` on pods — a merge patch with a null value deletes the
  // key. The primary Service selects that label, so clients always reach the
  // current master, even across the hand-off. HOME is a writable emptyDir so
  // kubectl can cache under a read-only root filesystem.
  local labelerScript = |||
    set -u
    export HOME=/home/labeler
    escaped='%(roleLabel)s'
    while true; do
      if printf 'INFO replication\r\n' | nc -w 2 127.0.0.1 6379 2>/dev/null | grep -q 'role:master'; then
        value='"primary"'
      else
        value=null
      fi
      kubectl patch pod "$POD_NAME" --type=merge \
        -p "{\"metadata\":{\"labels\":{\"$escaped\":$value}}}" >/dev/null 2>&1 || true
      sleep 3
    done
  ||| % { roleLabel: roleLabel };

  kurly.worker('valkey', image)
  + kurly.version(version)
  + kurly.runAs(999)
  // A writable scratch for the generated config (and Valkey's working dir); the
  // root filesystem stays read-only.
  + kurly.scratch('/gen')
  + kurly.command(['valkey-server', '/gen/valkey.conf'])
  + kurly.headlessService(port=6379, publishNotReady=true)
  + kurly.rollingUpdate(maxSurge=1, maxUnavailable=0)
  + kurly.terminationGracePeriod(120)
  + kurly.initContainer({
    name: 'discover-primary',
    image: image,
    command: ['sh', '-c', initScript],
    volumeMounts: [{ name: 'gen', mountPath: '/gen' }],
    securityContext: hardened,
  })
  + kurly.lifecycle(preStop={ exec: { command: ['sh', '-c', preStopScript] } })
  + kurly.readinessProbe({ exec: { command: ['sh', '-c', "valkey-cli info replication | grep -qE 'role:master|master_link_status:up'"] } })
  // The labeler is a Kubernetes API client: it needs a Role to patch pod labels
  // AND network egress to the apiserver. apiServerClient declares both as
  // cross-cutting requirements, so a consumer's own rbac()/networkPolicy() cannot
  // clobber this grant or firewall off the labeler. `patch` alone (no `get`, no
  // `list`, no `watch`) is the whole grant — a namespaced Role, scoped to pods. It
  // cannot be narrowed to this one pod: RBAC `resourceNames` cannot match the
  // controller's generated pod names, so the patch verb is namespace-wide on pods.
  + kurly.apiServerClient([{ apiGroups: [''], resources: ['pods'], verbs: ['patch'] }])
  // The labeler sidecar (a second container) and the primary Service are this
  // workload's own plumbing, added with the raw `+` escape hatch rather than a
  // library feature.
  + {
    deployment+: {
      spec+: { template+: { spec+: {
        containers+: [{
          name: 'role-labeler',
          image: kubectlImage,
          command: ['sh', '-c', labelerScript],
          env: [{ name: 'POD_NAME', valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } }],
          resources: { requests: { cpu: '10m', memory: '32Mi' }, limits: { memory: '32Mi' } },
          // A writable HOME so kubectl can cache under the read-only root
          // filesystem; the pod fsGroup (999) owns the emptyDir.
          volumeMounts: [{ name: 'labeler-home', mountPath: '/home/labeler' }],
          securityContext: {
            readOnlyRootFilesystem: true,
            allowPrivilegeEscalation: false,
            runAsNonRoot: true,
            runAsUser: 999,
            capabilities: { drop: ['ALL'] },
            seccompProfile: { type: 'RuntimeDefault' },
          },
        }],
        volumes+: [{ name: 'labeler-home', emptyDir: {} }],
      } } },
    },
    // Clients connect here; it resolves only to the pod the labeler marks primary.
    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { name: 'valkey', labels: { 'app.kubernetes.io/name': 'valkey', 'app.kubernetes.io/managed-by': 'kurly', 'app.kubernetes.io/version': version } },
      spec: {
        selector: { 'app.kubernetes.io/name': 'valkey', [roleLabel]: 'primary' },
        ports: [{ name: 'redis', port: 6379, targetPort: 6379 }],
      },
    },
  }
