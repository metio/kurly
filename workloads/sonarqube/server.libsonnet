// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sonarqube — a SonarQube server (continuous code-quality and static-analysis
// inspection). A plain composable kurly.http workload on the official Community
// image, backed by an external PostgreSQL, with its data, extensions, and embedded
// search index on a PersistentVolume. Import it, point it at a database, and render
// with kurly.list:
//
//   local sonarqube = import 'github.com/metio/kurly/workloads/sonarqube/server.libsonnet';
//   kurly.list(sonarqube())
//
// Serves the web UI and API on :9000 — compose an exposure onto it.
//
// DATABASE & SECRETS: SonarQube needs PostgreSQL. It reads SONAR_JDBC_URL and
// SONAR_JDBC_USERNAME from env and SONAR_JDBC_PASSWORD from a provided Secret via
// envFrom. The defaults pair with a cnpg-cluster named sonarqube-db. kurly authors
// no Secret.
//
// HOST REQUIREMENT: SonarQube's embedded Elasticsearch needs the node's
// `vm.max_map_count` at least 262144. Set it on the node (a DaemonSet, a node
// bootstrap, or the kubelet) — kurly deliberately does NOT inject a privileged
// initContainer to change it, which would break the hardened posture.
//
// Single writer: the search index and data live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='sonarqube',
  image='docker.io/library/sonarqube:26.7.0.124771-community',
  storageSize='10Gi',
  storageClass=null,
  dbHost='sonarqube-db-rw',
  dbName='sonarqube',
  dbUser='sonarqube',
  // The Secret holding SONAR_JDBC_PASSWORD (kurly mints none), via envFrom.
  secretName='sonarqube-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    SONAR_JDBC_URL: 'jdbc:postgresql://' + dbHost + ':5432/' + dbName,
    SONAR_JDBC_USERNAME: dbUser,
  };

  // SonarQube keeps extensions and logs beside its data; surface them as subpaths
  // of the same volume so plugins and audit logs survive a restart.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/opt/sonarqube/extensions', subPath: 'extensions' },
          { name: 'store', mountPath: '/opt/sonarqube/logs', subPath: 'logs' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/opt/sonarqube/data', storageSize, storageClass=storageClass)
  // SonarQube writes unpacked plugins and work files under /opt/sonarqube/temp;
  // back it with an emptyDir so the root filesystem stays read-only.
  + kurly.scratch('/opt/sonarqube/temp', '2Gi')
  + kurly.readinessProbe({ httpGet: { path: '/api/system/status', port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30, failureThreshold: 20 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
