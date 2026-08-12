// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// percona-server — a drop-in MySQL replacement with the instrumentation and
// storage-engine work Percona adds on top: better diagnostics, an audit plugin,
// and XtraDB. A composable kurly.stateful workload, because a database wants a
// stable identity and a volume that follows it. Import it and render with
// kurly.list:
//
//   local percona = import 'github.com/metio/kurly/workloads/percona-server/server.libsonnet';
//   kurly.list(percona(secretName='percona-server'))
//
// Serves MySQL on :3306 and the X protocol on :33060.
//
// ONE SERVER, NOT A CLUSTER. This is a single mysqld with its own volume. It has
// no replication, no failover and no automatic backup, so losing the node it is
// on means restoring from whatever somebody else took — compose a kurly.backup
// axis onto it, and reach for an operator when the database matters more than the
// simplicity does.
//
// THE ROOT PASSWORD IS READ ONCE. The entrypoint initialises the data directory on
// first start using the Secret's values and then never looks at them again:
// changing MYSQL_ROOT_PASSWORD later changes nothing, because the credential lives
// in the database from then on. That is the usual surprise with this image and it
// is not a kurly behaviour.
//
// Single writer: one data directory on one volume, so one replica. Scaling this
// number does not make a cluster, it makes several unrelated databases.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='percona-server',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // Created on first start, alongside the root account.
  database=null,
  user=null,
  // A Secret carrying MYSQL_ROOT_PASSWORD and, when `user` is set,
  // MYSQL_PASSWORD.
  secretName='percona-server',
  // Extra my.cnf settings, merged into the rendered configuration file.
  config={},
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(3306)
  + kurly.servicePort(3306)
  + kurly.extraPort('mysqlx', 33060)
  + kurly.env(
    {}
    + (if database != null then { MYSQL_DATABASE: database } else {})
    + (if user != null then { MYSQL_USER: user } else {})
    + env
  )
  + kurly.envFromSecret(secretName)
  // The uid the image's own mysql user carries; fsGroup so the data directory is
  // writable.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/var/lib/mysql', storageSize, storageClass=storageClass)
  + kurly.scratch('/var/log/mysql', '1Gi')
  + kurly.scratch('/tmp', '1Gi')
  + kurly.config(
    {
      'overrides.cnf': std.join('\n', ['[mysqld]'] + [
        '%s = %s' % [k, std.toString(config[k])]
        for k in std.objectFields(config)
      ]) + '\n',
    },
    mountPath='/etc/my.cnf.d'
  )
  // Probed by connection: mysqld accepts TCP only once the data directory is
  // initialised, and a first start that has to build it takes minutes.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
