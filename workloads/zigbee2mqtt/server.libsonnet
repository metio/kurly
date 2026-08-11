// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// zigbee2mqtt — bridges a Zigbee network onto MQTT, so Zigbee devices are usable
// by anything that speaks MQTT without the vendor's own hub or cloud. A plain
// composable kurly.http workload: it keeps its device database and settings in
// files under /app/data on a PersistentVolume and publishes everything else to
// the broker. Import it and render with kurly.list:
//
//   local zigbee2mqtt = import 'github.com/metio/kurly/workloads/zigbee2mqtt/server.libsonnet';
//   kurly.list(zigbee2mqtt(mqttServer='mqtt://mosquitto:1883', serialPort='tcp://zigbee-gw:6638'))
//
// Serves the frontend on :8080 — compose an exposure onto it.
//
// THE ADAPTER IS THE WHOLE QUESTION. zigbee2mqtt talks to a Zigbee radio, and a
// pod cannot be handed a USB stick that is plugged into some node — a workload
// that assumed one would run on exactly one machine and be un-schedulable
// everywhere else. So `serialPort` defaults to nothing and the deployment that
// works in a cluster is a NETWORK coordinator: a `tcp://host:port` adapter (a
// serial-over-IP bridge, a SLZB/ZiGate-style ethernet coordinator), which any
// node can reach. A USB adapter is still possible by pinning the pod to its node
// and adding the device, and that is a decision to make deliberately rather than
// a default to inherit.
//
// MQTT: `mqttServer` is required — zigbee2mqtt publishes everything it knows to
// the broker and does nothing useful without one.
//
// Single writer: one device database on a ReadWriteOnce volume, and two bridges
// driving one radio would fight over it, so one replica, recreated (never
// rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='zigbee2mqtt',
  image=defaultImage,
  // The MQTT broker to publish to, e.g. mqtt://mosquitto:1883.
  mqttServer='mqtt://mosquitto:1883',
  // The Zigbee adapter — a tcp://host:port network coordinator in a cluster.
  serialPort=null,
  // The adapter driver: ember, zstack, deconz, zigate or zboss.
  adapter=null,
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // zigbee2mqtt reads its whole configuration from ZIGBEE2MQTT_CONFIG_* when it
  // is set, writing the rest into configuration.yaml on the volume itself — so
  // the settings that must not drift are given here and the device database
  // stays where zigbee2mqtt manages it.
  + kurly.env(
    {
      ZIGBEE2MQTT_DATA: '/app/data',
      ZIGBEE2MQTT_CONFIG_MQTT_SERVER: mqttServer,
      ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED: 'true',
      ZIGBEE2MQTT_CONFIG_FRONTEND_PORT: '8080',
      ZIGBEE2MQTT_CONFIG_FRONTEND_HOST: '0.0.0.0',
    }
    + (if serialPort != null then { ZIGBEE2MQTT_CONFIG_SERIAL_PORT: serialPort } else {})
    + (if adapter != null then { ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER: adapter } else {})
    + env
  )
  // The image runs node as root by default; nothing in it is owned by a runtime
  // user, so an unprivileged uid with fsGroup over the data volume serves.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
