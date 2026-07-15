// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tik — the `tik backend` supervisor stage, as a COMPOSABLE app (not a rendered
// List). Import it, adapt your environment with `+` features, then render with
// kurly.list:
//
//   local tik = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';
//   kurly.list(tik() + kurly.expose.gateway('tik.internal', 'shared-gateway'))
//
// kurly is imported by its canonical path: that is what JaaS resolves via the
// kurly JsonnetLibrary, and local rendering resolves the same path through the
// vendor tree. One process serves the read-only board and runs the store's
// writers over a shared append-only event store; a single writer over a
// ReadWriteOnce store, so one replica, recreated (never rolled) to avoid
// deadlocking on the volume. Exposure is left out on purpose — compose your own.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version. 'dev' locally; the
// release pipeline rewrites it to the calver before packing the source.
local version = 'dev';

// The pipelines the supervisor runs, passed via --config as an EDN document in
// the mounted ConfigMap. The board serves continuously; the recur and probe
// pipelines fire on their interval, signing as the delegate `tik-backend`.
local pipelines = |||
  {:pipelines
   [{:id :board :watch true :run ["serve" "--port" "7777"]}
    {:id :release :every "PT1H" :run ["recur" "release-train"] :period :iso-week :as "tik-backend"}
    {:id :dashboard :every "PT6H" :run ["probe"] :as "tik-backend"}]}
|||;

function(image='ghcr.io/metio/tik:2026.7.14194001')
  kurly.http('tik', image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7777)
  + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
  + kurly.env({ TIK_ROOT: '/var/lib/tik', TIK_KEY: '/etc/tik-key/id_ed25519' })
  + kurly.store('/var/lib/tik', '1Gi')
  + kurly.config({ 'pipelines.edn': pipelines }, mountPath='/etc/tik')
  + kurly.secretMount('tik-signing-key', '/etc/tik-key', optional=true, defaultMode=256)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.runAs(12345)
  + kurly.probes('/tickets.edn')
  + kurly.resources(
    requests={ cpu: '200m', memory: '320Mi', 'ephemeral-storage': '256Mi' },
    limits={ cpu: '200m', memory: '320Mi', 'ephemeral-storage': '256Mi' },
  )
