// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// neo4j — a Neo4j server (the graph database) on the official Community image. Unlike
// the other database workloads, Neo4j Community has no Kubernetes operator and does
// not cluster (clustering is an Enterprise feature), so this is a plain composable
// kurly.http single-instance workload rather than a CR: its graph lives on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local neo4j = import 'github.com/metio/kurly/workloads/neo4j/server.libsonnet';
//   kurly.list(neo4j())
//
// Serves the HTTP/Browser API on :7474 and Bolt on :7687 — compose an exposure onto
// the HTTP port and route Bolt as TCP.
//
// Neo4j Community Edition is GPLv3 (fine to run; GPL obligations attach to
// distribution, not operation). For clustering / HA, Neo4j Enterprise is required —
// beyond this recipe.
//
// AUTH: Neo4j reads NEO4J_AUTH (`neo4j/<password>`) from the environment. kurly
// authors no Secret; provide one holding NEO4J_AUTH, pulled in via envFrom.
//
// Single writer: the graph lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the store.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='neo4j',
  image='docker.io/library/neo4j:5.26.28-community',
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding NEO4J_AUTH (kurly mints none), via envFrom.
  secretName='neo4j-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local boltPort = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { ports+: [{ containerPort: 7687, name: 'bolt', protocol: 'TCP' }] }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports+: [{ name: 'bolt', port: 7687, targetPort: 'bolt', protocol: 'TCP' }] } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7474)
  + kurly.servicePort(7474)
  + kurly.envFromSecret(secretName)
  + kurly.env({ NEO4J_server_default__listen__address: '0.0.0.0' } + env)
  // The image runs as uid 7474 (neo4j); pin it and its fsGroup so the data volume is
  // writable and the restricted posture admits the pod.
  + kurly.runAs(7474, gid=7474, fsGroup=7474)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'bolt' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'bolt' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + boltPort
