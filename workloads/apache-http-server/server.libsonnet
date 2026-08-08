// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// apache-http-server — an Apache HTTP Server (httpd: static files, rewriting, proxying and
// authentication through its module system). A plain composable kurly.http workload on the
// official image, serving the site the image already ships. Import it, pass your own
// configuration and content, and render with kurly.list:
//
//   local httpd = import 'github.com/metio/kurly/workloads/apache-http-server/server.libsonnet';
//   kurly.list(httpd())
//
// Serves on :8080 — compose an exposure onto it.
//
// CONFIG IS THE WORKLOAD: `config` is httpd's own configuration language, which kurly does
// not model — a second-hand copy would drift against Apache's and lie about what it accepts
// — so it is mounted verbatim and named on the command line with `-f`. The image's own
// /usr/local/apache2/conf is left intact underneath, so `Include conf/extra/...` and
// `TypesConfig conf/mime.types` still resolve; mounting over that directory instead would
// shadow mime.types and the extra/ snippets the shipped configuration refers to.
//
// THE SHIPPED CONFIGURATION CANNOT BE USED AS IT STANDS. It listens on :80, which an
// unprivileged uid cannot bind, and it puts the pid file, the scoreboard and both logs
// under /usr/local/apache2/logs, which the read-only root filesystem refuses. The default
// here is a complete minimal configuration instead: :8080, DefaultRuntimeDir and the pid
// file on the scratch at /tmp, and both logs to the container's own stdout/stderr, which is
// where a cluster reads them.
//
// Stateless: the served directory is the image's htdocs, so the workload keeps nothing and
// scales horizontally. Serving your own site means composing a kurly.config or a
// kurly.store onto it and pointing documentRoot at the mount.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// A working default: the modules a static site needs and nothing else, everything writable
// on the scratch, both logs on the container's own file descriptors.
local defaultConfig(port, documentRoot) = |||
  ServerRoot "/usr/local/apache2"
  ServerName localhost
  Listen %(port)d

  LoadModule mpm_event_module modules/mod_mpm_event.so
  LoadModule unixd_module modules/mod_unixd.so
  LoadModule authz_core_module modules/mod_authz_core.so
  LoadModule mime_module modules/mod_mime.so
  LoadModule dir_module modules/mod_dir.so
  LoadModule log_config_module modules/mod_log_config.so

  DefaultRuntimeDir /tmp
  PidFile /tmp/httpd.pid

  DocumentRoot "%(documentRoot)s"
  <Directory />
      AllowOverride none
      Require all denied
  </Directory>
  <Directory "%(documentRoot)s">
      Options FollowSymLinks
      AllowOverride None
      Require all granted
  </Directory>
  DirectoryIndex index.html

  TypesConfig conf/mime.types

  ErrorLog /proc/self/fd/2
  LogLevel warn
  LogFormat "%%h %%l %%u %%t \"%%r\" %%>s %%b" common
  CustomLog /proc/self/fd/1 common
||| % { port: port, documentRoot: documentRoot };

function(
  name='apache-http-server',
  image=defaultImage,
  port=8080,
  documentRoot='/usr/local/apache2/htdocs',
  config=null,
  env={},
  replicas=2,
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  // Mounted beside the image's own conf directory, never over it: the shipped mime.types
  // and extra/ snippets stay reachable for a configuration that includes them.
  + kurly.config(
    { 'httpd.conf': if config == null then defaultConfig(port, documentRoot) else config },
    mountPath='/etc/httpd',
  )
  // The image declares httpd-foreground as its CMD and no entrypoint, so arguments alone
  // would REPLACE the command rather than extend it — the container then tries to exec `-f`
  // and reports a missing executable. The wrapper is named again here; it execs
  // `httpd -DFOREGROUND "$@"`, so this names the configuration instead of the shipped one.
  + kurly.command(['httpd-foreground', '-f', '/etc/httpd/httpd.conf'])
  + (if env == {} then {} else kurly.env(env))
  // The image declares root and drops nothing itself, so the uid is pinned here. htdocs and
  // the modules are world-readable, so no group ownership is needed for them.
  + kurly.runAs(1000, gid=1000)
  // DefaultRuntimeDir (the scoreboard and the mutex locks) and the pid file: httpd exits at
  // startup if it cannot create them, and everything else it wants to write is a log, which
  // goes to a file descriptor rather than a file.
  + kurly.scratch('/tmp')
  // Probe by connection: which paths answer, and with what, is entirely the caller's
  // configuration — an httpGet on '/' is a 404 the moment somebody serves their own site.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
