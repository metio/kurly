// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sqlpage — a SQLPage server (build a web application by writing SQL files: each
// .sql file is a page, and its result rows render as tables, forms and charts).
// A plain composable kurly.http workload. Import it and render with kurly.list:
//
//   local sqlpage = import 'github.com/metio/kurly/workloads/sqlpage/server.libsonnet';
//   kurly.list(sqlpage(site={ 'index.sql': "select 'text' as component, 'hello' as contents;" }))
//
// Serves the site on :8080 — compose an exposure onto it.
//
// THE SITE IS THE CONFIGURATION. SQLPage runs whatever .sql files it finds in its
// web root, so `site` is the application itself, delivered as a ConfigMap. With no
// files it serves its own welcome page and nothing else.
//
// The database it queries is whatever DATABASE_URL points at — SQLite on the
// volume by default, or an external PostgreSQL or MySQL. That connection has
// whatever rights you grant it, and every page runs with those rights: SQLPage has
// no user model of its own, so authorisation is something the SQL has to do.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sqlpage',
  image=defaultImage,
  // The .sql files that make up the site, keyed by filename.
  site={},
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      // The SQLite file goes on the volume; the image's own default would put it
      // in the web root, where it would be served alongside the pages.
      DATABASE_URL: 'sqlite:///data/sqlpage.db?mode=rwc',
    } + env
  )
  + (if site == {} then {} else kurly.config(site, mountPath='/var/www', subPath=true))
  // The image already selects its own account.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
