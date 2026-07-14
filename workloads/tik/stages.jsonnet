// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tik — the first flagship kurly workload: the `tik backend` supervisor, one
// process that serves the read-only board and runs the store's writers (mail
// ingest, recurring tickets, dashboards, effects) over a shared append-only
// event store. Declared once by composing the base http kind with `+` features.
//
// Authored as a `function(params)` so JaaS can render it with the deployment's
// own values as TLAs; the workload artifact pipeline renders it with the
// defaults. tik is a SINGLE-stage workload — its manifests have no
// install-order dependency worth gating (the store's PVC binds
// WaitForFirstConsumer, so it must apply with the pod that consumes it, and the
// HTTPRoute simply has no endpoints until the board is ready). stageset-controller
// still deploys it with a pinned-revision gated apply, rollback, and the
// version-gated migration ladder in migrations.jsonnet.
local kurly = import '../../main.libsonnet';

// The pipelines the supervisor runs, passed via --config as an EDN document in
// the mounted ConfigMap. The board serves continuously; the recur and probe
// pipelines fire on their interval, signing as the delegate `tik-backend`.
local pipelines = |||
  {:pipelines
   [{:id :board :watch true :run ["serve" "--port" "7777"]}
    {:id :release :every "PT1H" :run ["recur" "release-train"] :period :iso-week :as "tik-backend"}
    {:id :dashboard :every "PT6H" :run ["probe"] :as "tik-backend"}]}
|||;

function(
  image='ghcr.io/metio/tik:2026.7.14174051',
  host='tik.example.com',
  gateway='shared-gateway',
  gatewayNamespace='infrastructure',
  storeSize='1Gi',
  signingKeySecret='tik-signing-key',
)
  local tik =
    kurly.http('tik', image)
    // One supervisor process: it bundles the board and the store's writers, and
    // two writers cannot share a ReadWriteOnce store — so it stays at a single
    // replica, recreated (never rolled) to avoid deadlocking on the volume.
    + kurly.replicas(1)
    + kurly.recreate()
    + kurly.port(7777)
    + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
    + kurly.env({ TIK_ROOT: '/var/lib/tik', TIK_KEY: '/etc/tik-key/id_ed25519' })
    // The append-only event store, its config, the delegate's signing key
    // (mounted from an existing Secret — kurly never mints key material), and a
    // writable /tmp the read-only root filesystem needs.
    + kurly.store('/var/lib/tik', storeSize)
    + kurly.config({ 'pipelines.edn': pipelines }, mountPath='/etc/tik')
    + kurly.secretMount(signingKeySecret, '/etc/tik-key', optional=true, defaultMode=256)
    + kurly.scratch('/tmp', '64Mi')
    // A fixed non-root uid/gid, and the matching fsGroup so the pod owns the
    // store volume's files.
    + kurly.runAs(12345)
    + kurly.probes('/tickets.edn')
    + kurly.resources(
      requests={ cpu: '200m', memory: '320Mi', 'ephemeral-storage': '256Mi' },
      limits={ cpu: '200m', memory: '320Mi', 'ephemeral-storage': '256Mi' },
    )
    + kurly.expose.gateway(host, gateway, gatewayNamespace=gatewayNamespace);

  { backend: kurly.list(tik) }
