// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// evcc — an evcc server (a solar-aware charging controller for electric vehicles: it
// reads your inverter, meters and wallboxes, and shifts charging into the hours your own
// production covers). A plain composable kurly.http workload on the official image, with
// its SQLite database on a PersistentVolume. Import it and render with kurly.list:
//
//   local evcc = import 'github.com/metio/kurly/workloads/evcc/server.libsonnet';
//   kurly.list(evcc())
//
// Serves the web UI and API on :7070 — compose an exposure onto it.
//
// CONFIG IS THE WORKLOAD: `config` is evcc's own schema (site, meters, chargers,
// vehicles, loadpoints, tariffs), which kurly does not model — a second-hand copy would
// drift against evcc's and lie about what it accepts — so it is mounted verbatim as
// /etc/evcc.yaml, the path evcc searches. It is null by default: with no config file evcc
// boots into its configuration UI and writes what you enter into the database, which is
// the path most deployments take. The database is pinned onto the volume with
// EVCC_DATABASE_DSN (evcc maps every config key to an EVCC_-prefixed variable), so it
// never lands in the container's HOME where a restart would lose it.
//
// The hardware evcc talks to lives on the LAN, and its discovery protocols (mDNS, SMA
// Speedwire, KEBA, EEBus) are broadcast UDP that a pod network does not carry. Devices
// addressed by IP work as they are; discovery needs host networking, which is the
// consumer's call to compose and not a default worth shipping.
//
// Single writer: SQLite on a ReadWriteOnce volume, so one replica, recreated (never
// rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='evcc',
  image=defaultImage,
  // The SQLite database, and whatever the configuration UI stores with it.
  storageSize='1Gi',
  storageClass=null,
  // evcc's own settings as an object, rendered to /etc/evcc.yaml verbatim. null leaves
  // the file out and evcc starts in configuration mode.
  config=null,
  // Charging schedules are wall-clock decisions, so the container's zone matters.
  timezone='Europe/Berlin',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7070)
  + kurly.servicePort(7070)
  + kurly.env(
    {
      TZ: timezone,
      EVCC_DATABASE_DSN: '/data/evcc.db',
    } + env
  )
  // Mounted as a single FILE: /etc also holds the CA bundle evcc needs to reach cloud
  // tariffs and vehicle APIs, and a directory mount would replace it.
  + (
    if config == null then {}
    else kurly.config({ 'evcc.yaml': std.manifestYamlDoc(config) }, mountPath='/etc', subPath=true)
  )
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // The Go binary writes its scratch files to the temporary directory, and the root
  // filesystem stays read-only.
  + kurly.scratch('/tmp')
  // A Service named after the workload would otherwise inject EVCC_PORT as a tcp:// URL,
  // which evcc reads as a config key.
  + kurly.disableServiceLinks()
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
