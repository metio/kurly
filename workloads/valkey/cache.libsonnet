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
  image='docker.io/valkey/valkey:8',
  maxMemory='256mb',
)
  local headless = 'valkey-headless';

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
