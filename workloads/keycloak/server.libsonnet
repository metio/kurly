// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// keycloak — a Keycloak identity server as an official keycloak-operator
// `Keycloak` custom resource. Like the other operator-backed workloads (loki,
// tempo, cnpg-cluster), this authors the CR directly; the operator reconciles it
// into a StatefulSet, Services, and the admin credentials Secret. Import it, point
// it at a database, and render with kurly.list:
//
//   local keycloak = import 'github.com/metio/kurly/workloads/keycloak/server.libsonnet';
//   kurly.list(keycloak(hostname='https://id.example.com', tlsSecret='id-tls'))
//
// PREREQUISITE: the keycloak-operator (its CRDs and controller) installed. Its
// recent releases let ONE operator manage Keycloak CRs across many namespaces, so
// a single cluster-wide install serves every tenant.
//
// DATABASE: Keycloak needs a PostgreSQL database. This pairs with the
// cnpg-cluster workload — the defaults point at a CNPG cluster named `keycloak-db`
// (its `-rw` Service) and read credentials from the `-app` Secret CNPG mints
// (keys username, password). kurly never authors those Secrets; the database
// (and any TLS Secret) are the consumer's to provide.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver. (The Keycloak image itself is
// the operator's to choose from its version, unless `image` pins one.)
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='keycloak',
  instances=1,
  // Pins the Keycloak image; null leaves the operator to choose the one matching
  // its version (the usual choice, and the air-gap knob is on the operator).
  image=null,
  // The PostgreSQL database. dbHost defaults to a cnpg-cluster named `keycloak-db`
  // (its read-write Service); dbSecret to the `-app` Secret CNPG mints, whose
  // username/password keys Keycloak reads.
  dbHost='keycloak-db-rw',
  dbName='keycloak',
  dbSecret='keycloak-db-app',
  // The public URL Keycloak builds links against — required in production. Left
  // null, Keycloak infers it from the request (fine for a first bring-up).
  hostname=null,
  // The Secret holding the TLS certificate Keycloak terminates on. Null serves
  // plain HTTP (httpEnabled) — correct behind a TLS-terminating gateway or ingress
  // (add proxy.headers through `spec`), a choice rather than a hidden default.
  tlsSecret=null,
  labels={},
  annotations={},
  // Extra Keycloak spec fields, merged over the below (proxy.headers, ingress,
  // hostname.admin/strict, additionalOptions, resources, unsupported, …). The
  // operator's schema is deep; kurly does not model it, the same as loki's and
  // tempo's `spec`.
  spec={},
)
  {
    // Composed kurly features cannot reach an operator's pods (they write a
    // config no base here reads), so composing one would silently do nothing;
    // fail the render and point at the parameters that work. Same guard as loki,
    // tempo, and cnpg-cluster.
    assert !std.objectHasAll(self, 'config') :
           "keycloak: kurly features do not apply to a custom resource — use this workload's own parameters (instances, dbHost/dbName/dbSecret, hostname, tlsSecret, labels/annotations) instead.",

    keycloak: {
      apiVersion: 'k8s.keycloak.org/v2beta1',
      kind: 'Keycloak',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
              instances: instances,
              db: {
                vendor: 'postgres',
                host: dbHost,
                database: dbName,
                usernameSecret: { name: dbSecret, key: 'username' },
                passwordSecret: { name: dbSecret, key: 'password' },
              },
              // TLS terminated by Keycloak when a cert Secret is named; otherwise
              // plain HTTP, for a TLS-terminating proxy in front.
              http: (if tlsSecret == null then { httpEnabled: true } else { tlsSecret: tlsSecret }),
            }
            + (if hostname == null then {} else { hostname: { hostname: hostname } })
            + (if image == null then {} else { image: image })
            + spec,
    },
  }
